# frozen_string_literal: true

# Regression coverage for accent-insensitive search (lib/queries.rb).
#
# Root cause of the 2026-07-09 bug report ("searching 'Maria' finds nothing
# even though the DB has many accented 'María's"): accent-insensitive
# matching used to be opt-in per field, gated on an ACCENT_SENSITIVE_LABELS
# allowlist keyed on the ontology's human-readable field label. That allowlist
# was fragile in three independent ways, any one of which silently dropped a
# field back to plain (accent-sensitive) CONTAINS/LCASE matching:
#   1. It was never extended to cover member_name/member_surnames.
#   2. It broke under label rewording: the list had 'affiliation' but the
#      live label is 'Affiliations' (plural); it had 'partner institutions'
#      but the live label is 'Partner institutions (acronym and country)'.
#      Both are exact-string comparisons, so neither matched.
#   3. It only listed English label text, so it silently stopped applying
#      whenever current_language was 'es' (labels become 'Nombre', 'Título',
#      etc.).
#
# The fix removes the allowlist entirely: every free-text/dropdown search
# condition now goes through the accent-insensitive regex path
# unconditionally (currency and date fields have their own dedicated
# branches and are untouched). These specs pin that behavior so a future
# change can't reintroduce a per-field opt-in list.
RSpec.describe 'accent-insensitive search' do
  # Extracts every "?attribute_N rdf:type cbgp:questionclass" assertion from a
  # generated query and maps questionclass => variable(s), so specs below can
  # assert two different fields never end up sharing one variable (the exact
  # shape of the 2026-09-28 variable-collision bug, see the describe block
  # below) - structurally, not tied to one specific field pair, so a future
  # field added to the ontology is covered automatically. Shared by both the
  # multi-field and the negation describe blocks below.
  def field_variable_map(query)
    query.scan(/(\?attribute_\d+)\s+rdf:type\s+cbgp:(\w+)/).each_with_object({}) do |(var, questionclass), map|
      map[questionclass] ||= []
      map[questionclass] << var
    end
  end

  def expect_each_field_to_have_its_own_variable(query, expected_questionclasses)
    map = field_variable_map(query)
    expect(map.keys.sort).to eq(expected_questionclasses.sort)

    all_vars = map.values.flatten
    expect(all_vars.uniq.size).to eq(all_vars.size),
                                  "expected every field to use a distinct ?attribute_N variable, got: #{map.inspect}"
  end

  describe '#unaccent' do
    it 'strips Spanish diacritics down to base letters' do
      expect(unaccent('María')).to eq('Maria')
      expect(unaccent('Muñoz')).to eq('Munoz')
      expect(unaccent('Peña')).to eq('Pena')
    end

    it 'leaves plain ASCII untouched' do
      expect(unaccent('Maria')).to eq('Maria')
    end
  end

  describe '#accent_insensitive_pattern' do
    it 'builds a character-class pattern that matches both accented and unaccented forms' do
      pattern = accent_insensitive_pattern('maria')
      regex = Regexp.new(pattern, Regexp::IGNORECASE)

      expect('María').to match(regex)
      expect('Maria').to match(regex)
      expect('MARIA').to match(regex)
      expect('Mario').not_to match(regex)
    end

    it 'matches when the search term itself is typed with an accent' do
      pattern = accent_insensitive_pattern('maría')
      regex = Regexp.new(pattern, Regexp::IGNORECASE)

      expect('Maria').to match(regex)
      expect('María').to match(regex)
    end

    it 'returns an empty pattern for blank input' do
      expect(accent_insensitive_pattern('')).to eq('')
      expect(accent_insensitive_pattern('   ')).to eq('')
      expect(accent_insensitive_pattern(nil)).to eq('')
    end

    it 'escapes regex metacharacters and quotes so they cannot break out of the SPARQL literal' do
      pattern = accent_insensitive_pattern('a.b"c')
      expect(pattern).to include('\\.')
      expect(pattern).to include('\\"')
    end

    # A single backslash (e.g. "\.") is not a valid SPARQL string-literal
    # escape (ECHAR only covers \t \n \r \b \f \" \' \\) - GraphDB passed it
    # through leniently, but Virtuoso rejects it outright with SP030 "Bad
    # escape sequence", found 2026-08-26 testing a real bulk publication
    # load (a DOI like "10.1038/sdata..." contains regex metacharacters -
    # the literal dots - that triggered this on every single search/existence
    # check). The backslash must be doubled so Virtuoso's string parser
    # reduces \\ -> \ before the regex engine sees it.
    it 'doubles the backslash before a regex metacharacter, for Virtuoso SPARQL string-literal safety' do
      pattern = accent_insensitive_pattern('10.1038/sdata.2016.18')

      # Every literal "." in the term must be preceded by an EVEN number of
      # backslashes in the generated pattern (2, not 1) - an odd count means
      # a lone backslash would reach Virtuoso's SPARQL string-literal parser
      # as an invalid escape sequence.
      pattern.scan(/(\\*)\./).each do |match|
        backslashes = match[0]
        expect(backslashes.length.even?).to be(true),
                                            "expected an even backslash count before '.', got #{backslashes.length}"
      end
      expect(pattern).to include('\\\\.')
    end
  end

  describe '#build_search_query' do
    # Every dataset type/field combo that carries free text in production:
    # member names/surnames (the reported bug), plus the fields the old
    # allowlist *intended* to cover but, per the header comment, silently
    # didn't (affiliations, partner institutions) or did (title).
    free_text_cases = [
      { dataset_type: 'member', questionclass: 'member_name', params: { 'member_name' => 'maria' } },
      { dataset_type: 'member', questionclass: 'member_surnames', params: { 'member_surnames' => 'nino' } },
      { dataset_type: 'publication', questionclass: 'publication_title',
        params: { 'publication_title' => 'genetica' } },
      { dataset_type: 'publication', questionclass: 'publication_affiliations',
        params: { 'publication_affiliations' => 'nino' } },
      # project_partner_institutions no longer exists (Sara's 2026-08
      # project-fields restructuring); project_internal_code is another
      # Multiple/FREE text field, on personnel_project.
      { dataset_type: 'personnel_project', questionclass: 'project_internal_code',
        params: { 'project_internal_code' => 'espana' } }
    ]

    free_text_cases.each do |c|
      it "searches #{c[:questionclass]} with an accent-insensitive regex filter, not plain CONTAINS/LCASE" do
        query = build_search_query(search_params: c[:params], dataset_type: c[:dataset_type])

        expect(query).to include('FILTER regex(STR(?value_0)')
        expect(query).not_to include('FILTER(CONTAINS(LCASE(STR(?value_0))')
      end
    end

    it 'generates a query for "maria" whose regex pattern actually matches a stored "María"' do
      query = build_search_query(search_params: { 'member_name' => 'maria' }, dataset_type: 'member')

      pattern = query[/FILTER regex\(STR\(\?value_0\), "(.*?)", "i"\)/, 1]
      expect(pattern).not_to be_nil
      expect('María').to match(Regexp.new(pattern, Regexp::IGNORECASE))
    end

    it 'still matches a currency field with the dedicated numeric CONTAINS filter, unaffected by the accent change' do
      query = build_search_query(search_params: { 'personnel_project_total_funding' => '15,000.5' },
                                 dataset_type: 'personnel_project')

      expect(query).to include('FILTER(CONTAINS(STR(?value_0), "15000.50"))')
      expect(query).not_to include('FILTER regex(')
    end

    it 'still builds a date-range filter on ?datevalue_0, unaffected by the accent change' do
      query = build_search_query(
        search_params: { 'member_start_date' => { 'start' => '2020-01-01', 'end' => '2020-12-31' } },
        dataset_type: 'member'
      )

      expect(query).to include('?datevalue_0 >= "2020-01-01"^^xsd:date')
      expect(query).to include('?datevalue_0 <= "2020-12-31"^^xsd:date')
    end

    it 'applies accent-insensitive matching regardless of the current UI language' do
      Thread.current[:language] = 'es'
      query = build_search_query(search_params: { 'member_name' => 'maria' }, dataset_type: 'member')

      expect(query).to include('FILTER regex(STR(?value_0)')
    end

    it 'anchors every search query to the dataset type via an unconditional ?dataset triple' do
      query = build_search_query(search_params: { 'member_name' => 'maria' }, dataset_type: 'member')

      expect(query).to include('?dataset a cbgp:member .')
    end
  end

  describe '#build_search_query with multiple fields (regression coverage for the variable-collision bug)' do
    # 2026-09-28: build_search_query used to reuse the literal variable names
    # ?attribute/?value/?datevalue for EVERY field's condition block. Combining
    # 2+ non-date fields therefore forced a single ?attribute binding to
    # simultaneously satisfy two different `rdf:type cbgp:...` constraints -
    # impossible under this reified attribute-value model - so any 2-field
    # search silently returned zero rows. Nothing caught this because no spec
    # ever combined 2+ non-date params. Found while building NOT support
    # (which independently needs each field's variables scoped to its own
    # block anyway, so one field's FILTER NOT EXISTS can't leak into another
    # field's match).

    # field-type pairings x dataset types, so the guard isn't scoped to just
    # one form's field set.
    multi_field_cases = [
      { dataset_type: 'member', label: 'text + text',
        params: { 'member_name' => 'maria', 'member_surnames' => 'garcia' } },
      { dataset_type: 'member', label: 'text + date range',
        params: { 'member_name' => 'maria',
                  'member_start_date' => { 'start' => '2020-01-01', 'end' => '2020-12-31' } } },
      { dataset_type: 'personnel_project', label: 'text + currency',
        params: { 'project_title' => 'genomics', 'personnel_project_total_funding' => '1000' } },
      { dataset_type: 'personnel_project', label: 'currency + date range',
        params: { 'personnel_project_total_funding' => '1000',
                  'project_start_date' => { 'start' => '2020-01-01', 'end' => '2020-12-31' } } },
      { dataset_type: 'personnel_project', label: 'three fields at once (text + currency + date range)',
        params: { 'project_title' => 'genomics', 'personnel_project_total_funding' => '1000',
                  'project_start_date' => { 'start' => '2020-01-01', 'end' => '2020-12-31' } } }
    ]

    multi_field_cases.each do |c|
      it "gives each field its own SPARQL variables when searching #{c[:label]} on #{c[:dataset_type]}" do
        query = build_search_query(search_params: c[:params], dataset_type: c[:dataset_type])

        expect_each_field_to_have_its_own_variable(query, c[:params].keys)
      end
    end

    it 'still combines multiple positive fields with AND semantics (both conditions present, not just the last one)' do
      query = build_search_query(
        search_params: { 'member_name' => 'maria', 'member_surnames' => 'garcia' },
        dataset_type: 'member'
      )

      expect(query).to include('rdf:type cbgp:member_name')
      expect(query).to include('rdf:type cbgp:member_surnames')
    end
  end

  describe '#build_search_query with negation (NOT search)' do
    it 'wraps a negated text field in FILTER NOT EXISTS instead of negating the regex directly' do
      query = build_search_query(
        search_params: { 'member_institutional_mail_address' => 'upm.es',
                         'member_institutional_mail_address__not' => '1' },
        dataset_type: 'member'
      )

      expect(query).to include('FILTER NOT EXISTS {')
      expect(query).to match(
        /FILTER NOT EXISTS \{[^}]*rdf:type cbgp:member_institutional_mail_address[^}]*FILTER regex/m
      )
      expect(query).not_to include('FILTER(!regex(')
      expect(query).not_to include('FILTER (!regex(')
    end

    it 'wraps a negated currency field in FILTER NOT EXISTS around the CONTAINS filter' do
      query = build_search_query(
        search_params: { 'personnel_project_total_funding' => '1000', 'personnel_project_total_funding__not' => '1' },
        dataset_type: 'personnel_project'
      )

      expect(query).to match(/FILTER NOT EXISTS \{[^}]*FILTER\(CONTAINS\(STR\(\?value_0\), "1000\.00"\)\)/m)
    end

    it 'wraps a negated date range in FILTER NOT EXISTS around the range filter' do
      query = build_search_query(
        search_params: {
          'member_start_date' => { 'start' => '2020-01-01', 'end' => '2020-12-31' },
          'member_start_date__not' => '1'
        },
        dataset_type: 'member'
      )

      expect(query).to match(/FILTER NOT EXISTS \{[^}]*\?datevalue_0 >= "2020-01-01"\^\^xsd:date[^}]*\}/m)
    end

    it 'combines a positive field and a negative field, each scoped to its own variables' do
      query = build_search_query(
        search_params: { 'member_name' => 'maria', 'member_institutional_mail_address' => 'upm.es',
                         'member_institutional_mail_address__not' => '1' },
        dataset_type: 'member'
      )

      # the positive field's regex is NOT inside the NOT EXISTS block
      expect(query).to include('FILTER regex(STR(?value_0)')
      expect(query).to include('FILTER NOT EXISTS {')
      not_exists_block = query[/FILTER NOT EXISTS \{(.*?)\n\}/m, 1]
      expect(not_exists_block).to include('member_institutional_mail_address')
      expect(not_exists_block).not_to include('member_name')
    end

    it 'combines two negative fields, each getting its own FILTER NOT EXISTS block with distinct variables' do
      query = build_search_query(
        search_params: { 'member_name' => 'maria', 'member_name__not' => '1',
                         'member_surnames' => 'garcia', 'member_surnames__not' => '1' },
        dataset_type: 'member'
      )

      expect(query.scan('FILTER NOT EXISTS {').size).to eq(2)
      expect_each_field_to_have_its_own_variable(query, %w[member_name member_surnames])
    end

    it 'treats a NOT flag with no corresponding field value as a no-op, not an error' do
      query = build_search_query(
        search_params: { 'member_institutional_mail_address__not' => '1' },
        dataset_type: 'member'
      )

      expect(query).to be_nil
    end

    it 'still anchors the query to the dataset type when every field is negated' do
      query = build_search_query(
        search_params: { 'member_name' => 'maria', 'member_name__not' => '1' },
        dataset_type: 'member'
      )

      expect(query).to include('?dataset a cbgp:member .')
    end
  end
end
