# frozen_string_literal: true

# escape_for_literal (lib/queries.rb) makes a value safe to embed inside a
# SPARQL string literal — every field value written by
# write_dataset_to_db_query, and the SCD history reason/detail strings, go
# through it. Covered here as its own pure-function spec since it's a single
# shared choke point for a lot of write paths.
RSpec.describe '#escape_for_literal' do
  it 'escapes a double quote so it cannot break out of the SPARQL string literal' do
    expect(escape_for_literal('a"b')).to eq('a\\"b')
  end

  it 'escapes a backslash' do
    expect(escape_for_literal('a\\b')).to eq('a\\\\b')
  end

  it 'escapes a backslash immediately followed by a quote without dropping either' do
    # Regression: an earlier implementation used gsub('\\', '\\\\') as a
    # *string* replacement, which gsub re-interprets as backslash escape
    # sequences — so the "doubled" backslash collapsed back down to a single
    # one on the way out, i.e. this input round-tripped as if unescaped.
    expect(escape_for_literal('a\\"b')).to eq('a\\\\\\"b')
  end

  it 'leaves ordinary text untouched' do
    expect(escape_for_literal('plain text, no special chars')).to eq('plain text, no special chars')
  end

  it 'stringifies non-string input first' do
    expect(escape_for_literal(42)).to eq('42')
  end

  it 'round-trips correctly when the escaped output is embedded and re-parsed as a SPARQL literal' do
    original = 'She said "hi" then typed C:\\path\\to\\file'
    escaped = escape_for_literal(original)
    turtle = %(<urn:test:s> <urn:test:p> "#{escaped}" .)

    graph = RDF::Graph.new << RDF::Turtle::Reader.new(turtle)
    expect(graph.first.object.to_s).to eq(original)
  end
end
