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
      { dataset_type: 'project', questionclass: 'project_partner_institutions',
        params: { 'project_partner_institutions' => 'espana' } }
    ]

    free_text_cases.each do |c|
      it "searches #{c[:questionclass]} with an accent-insensitive regex filter, not plain CONTAINS/LCASE" do
        query = build_search_query(search_params: c[:params], dataset_type: c[:dataset_type])

        expect(query).to include('FILTER regex(STR(?value)')
        expect(query).not_to include('FILTER(CONTAINS(LCASE(STR(?value))')
      end
    end

    it 'generates a query for "maria" whose regex pattern actually matches a stored "María"' do
      query = build_search_query(search_params: { 'member_name' => 'maria' }, dataset_type: 'member')

      pattern = query[/FILTER regex\(STR\(\?value\), "(.*?)", "i"\)/, 1]
      expect(pattern).not_to be_nil
      expect('María').to match(Regexp.new(pattern, Regexp::IGNORECASE))
    end

    it 'still matches a currency field with the dedicated numeric CONTAINS filter, unaffected by the accent change' do
      query = build_search_query(search_params: { 'project_total_funding' => '15,000.5' }, dataset_type: 'project')

      expect(query).to include('FILTER(CONTAINS(STR(?value), "15000.50"))')
      expect(query).not_to include('FILTER regex(')
    end

    it 'still builds a date-range filter on ?datevalue, unaffected by the accent change' do
      query = build_search_query(
        search_params: { 'member_start_date' => { 'start' => '2020-01-01', 'end' => '2020-12-31' } },
        dataset_type: 'member'
      )

      expect(query).to include('FILTER (?datevalue >= "2020-01-01"^^xsd:date && ?datevalue <= "2020-12-31"^^xsd:date)')
    end

    it 'applies accent-insensitive matching regardless of the current UI language' do
      Thread.current[:language] = 'es'
      query = build_search_query(search_params: { 'member_name' => 'maria' }, dataset_type: 'member')

      expect(query).to include('FILTER regex(STR(?value)')
    end
  end
end
