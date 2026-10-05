# frozen_string_literal: true

# A repeatable (cardinality Multiple) field posts its search values as an
# Array. build_search_query used to interpolate that Array into the regex as
# its Ruby inspect string (["x"]) - Virtuoso rejected the query, and the
# error surfaced as an unrelated Encoding::CompatibilityError 500. Found
# 2026-10-05 searching a repeatable cross-reference (project_pi_nie[]) from
# the new name-typeahead search widget.
RSpec.describe 'build_search_query with Array (repeatable-field) values' do
  def query(params)
    build_search_query(search_params: params, dataset_type: 'national_regional_research_project')
  end

  it 'searches each non-blank value as its own term' do
    q = query('project_pi_nie' => ['00831666D'])
    expect(q).to include('FILTER regex(STR(?value_0), "00831666d", "i")')
    expect(q).not_to include('[')
  end

  it 'requires every given value to match (one condition each)' do
    q = query('project_pi_nie' => %w[AAA BBB])
    expect(q).to include('?attribute_0 rdf:type cbgp:project_pi_nie', '?attribute_1 rdf:type cbgp:project_pi_nie')
  end

  it 'ignores blank rows (the empty row a repeatable widget always shows)' do
    q = query('project_pi_nie' => ['', '  '], 'project_title' => 'Foo')
    expect(q).to include('cbgp:project_title')
    expect(q).not_to include('cbgp:project_pi_nie')
  end

  it 'builds no query at all when the only terms are blank rows' do
    expect(query('project_pi_nie' => [''])).to be_nil
  end

  it 'still treats a plain String value as before' do
    expect(query('project_title' => 'Foo')).to include('cbgp:project_title')
  end

  it 'keeps NOT on an Array-valued field' do
    q = query('project_pi_nie' => ['AAA'], 'project_pi_nie__not' => '1')
    expect(q).to include('FILTER NOT EXISTS')
  end
end

# The regex pattern is embedded inside a double-quoted SPARQL string literal,
# so a quote or backslash in a search term must be escaped for the SPARQL
# string layer (and a backslash additionally for the regex layer). The bare
# `\\"` the escaper used to emit for a quote ended the literal early; the old
# spec only checked the output *contained* `\"`, which `\\"` also does. Found
# 2026-10-05 when a stringified array (["UI-PROJ-1"]) was posted by the
# typeahead. These check the one thing that matters: the query still parses.
RSpec.describe 'search terms with quotes, backslashes and brackets' do
  ['a"b', 'a\\b', '["UI-PROJ-1"]', 'a.b', "it's", 'back\\"quote', '\\\\'].each do |term|
    it "produces a parseable query for #{term.inspect}" do
      q = build_search_query(search_params: { 'project_title' => term }, dataset_type: 'personnel_project')
      expect { SPARQL.parse(q) }.not_to raise_error
    end
  end

  it 'escapes a double quote with exactly one backslash' do
    expect(sparql_regex_escape('"')).to eq('\\"')
  end

  it 'escapes a backslash with four (regex layer doubled for the SPARQL layer)' do
    expect(sparql_regex_escape('\\')).to eq('\\\\\\\\')
  end
end
