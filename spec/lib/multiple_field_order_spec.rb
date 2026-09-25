# frozen_string_literal: true

# Covers Multiple-cardinality field read order, fixed 2026-08-26. Author
# order matters for real biology papers (first/last author position is
# significant) - Crossref/DataCite already preserve it and the parsers
# already build dataset.authors in the right order (see crossref_parser.rb/
# datacite_parser.rb), and write_dataset_to_db_query already embeds that
# order in each attribute node's own URI ("..._1", "..._2", ...). But
# fetch_datasets_raw_data - the shared batch-fetch used every time a record
# is loaded - used to just flatten SPARQL result rows in whatever order
# Virtuoso's query planner returned them, with no ORDER BY and no use of the
# index already sitting in each attribute's URI. This spec pins the fix:
# read order is reconstructed from that URI suffix, not left to chance.
RSpec.describe 'Multiple-cardinality field read order' do
  # Deliberately out of order and with the attribute variable name
  # ("attributepublication_authors") that fetch_datasets_raw_data's SPARQL
  # query builds for the publication_authors field.
  let(:rows) do
    [
      RDF::Query::Solution.new(
        graph: RDF::URI('http://example.org/pub/1'),
        publication_authors: RDF::Literal.new('Third Author'),
        attributepublication_authors: RDF::URI('http://example.org/pub/1/publication_authors_3')
      ),
      RDF::Query::Solution.new(
        graph: RDF::URI('http://example.org/pub/1'),
        publication_authors: RDF::Literal.new('First Author'),
        attributepublication_authors: RDF::URI('http://example.org/pub/1/publication_authors_1')
      ),
      RDF::Query::Solution.new(
        graph: RDF::URI('http://example.org/pub/1'),
        publication_authors: RDF::Literal.new('Second Author'),
        attributepublication_authors: RDF::URI('http://example.org/pub/1/publication_authors_2')
      )
    ]
  end

  it 'returns Multiple-cardinality values in their original write-time order, not SPARQL row order' do
    allow(DATABASE).to receive(:query).and_return(rows)

    result = fetch_datasets_raw_data(graph_uris: ['http://example.org/pub/1'], database: 'publication')

    expect(result.first[:publication_authors]).to eq(['First Author', 'Second Author', 'Third Author'])
  end

  it 'sorts a row with no numeric suffix (or no attribute bound) to the end, rather than raising' do
    malformed_rows = rows + [
      RDF::Query::Solution.new(
        graph: RDF::URI('http://example.org/pub/1'),
        publication_authors: RDF::Literal.new('Malformed Suffix Author'),
        attributepublication_authors: RDF::URI('http://example.org/pub/1/publication_authors_not-a-number')
      )
    ]
    allow(DATABASE).to receive(:query).and_return(malformed_rows)

    result = fetch_datasets_raw_data(graph_uris: ['http://example.org/pub/1'], database: 'publication')

    expect(result.first[:publication_authors].last).to eq('Malformed Suffix Author')
    expect(result.first[:publication_authors]).to eq(
      ['First Author', 'Second Author', 'Third Author', 'Malformed Suffix Author']
    )
  end
end
