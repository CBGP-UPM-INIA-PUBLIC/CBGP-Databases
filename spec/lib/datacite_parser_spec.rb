# frozen_string_literal: true

# Covers datacite_parser after two fixes:
#  - it used to parse each author's ORCID and then discard it, only ever
#    keeping the bare name string; personnel cross-referencing needs that
#    ORCID, so it's now returned alongside the dataset (see lib/loaders.rb).
#  - a transient/permanent HTTP error used to retry up to 5 times immediately
#    with no backoff; capped at 2 attempts.
RSpec.describe 'CBGP::Parsers.datacite_parser' do
  let(:datacite_body) do
    {
      title: 'A Paper About Things',
      'container-title': 'Journal of Things',
      DOI: '10.1234/example',
      created: { 'date-time': '2024-03-15T00:00:00Z' },
      author: [
        { given: 'María', family: 'García', ORCID: 'https://orcid.org/0000-0001-2345-6789' },
        { given: 'Jane', family: 'Outsider' }
      ]
    }.to_json
  end

  before do
    allow(RestClient).to receive(:get)
      .with('https://doi.org/10.1234/example', anything)
      .and_return(datacite_body)
  end

  it 'builds a publication Dataset with title, journal, date and doi' do
    result = CBGP::Parsers.datacite_parser(doi: '10.1234/example')

    expect(result[:pub]).to be_a(CBGP::Dataset)
    expect(result[:pub].title).to eq('A Paper About Things')
    expect(result[:pub].journal).to eq('Journal of Things')
    expect(result[:pub].date).to eq('2024-03-15')
    expect(result[:pub].doi).to eq('10.1234/example')
  end

  it 'no longer discards each author ORCID - returns it alongside the dataset' do
    result = CBGP::Parsers.datacite_parser(doi: '10.1234/example')

    expect(result[:authors]).to eq([
                                      { name: 'María García', given: 'María', family: 'García', orcid: '0000-0001-2345-6789' },
                                      { name: 'Jane Outsider', given: 'Jane', family: 'Outsider', orcid: '' }
                                    ])
  end

  it 'still stores the plain display-name list on the dataset for the free-text authors field' do
    result = CBGP::Parsers.datacite_parser(doi: '10.1234/example')
    expect(result[:pub].authors).to eq(['María García', 'Jane Outsider'])
  end

  it 'gives up after 2 attempts instead of hammering doi.org 5 times' do
    allow(RestClient).to receive(:get).and_raise(RestClient::NotFound)

    result = CBGP::Parsers.datacite_parser(doi: '10.9999/gone')
    expect(result).to eq({ pub: false, authors: [] })
    expect(RestClient).to have_received(:get).at_most(2).times
  end

  it 'returns pub: false when there is no container-title (journal)' do
    allow(RestClient).to receive(:get)
      .with('https://doi.org/10.9999/no-journal', anything)
      .and_return({ title: 'x' }.to_json)

    result = CBGP::Parsers.datacite_parser(doi: '10.9999/no-journal')
    expect(result).to eq({ pub: false, authors: [] })
  end
end
