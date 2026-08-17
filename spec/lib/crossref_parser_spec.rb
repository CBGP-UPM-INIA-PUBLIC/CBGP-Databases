# frozen_string_literal: true

# Covers crossref_parser, the new direct api.crossref.org parser added
# alongside the DOI-registration-agency check in lib/loaders.rb, so
# Crossref-registered DOIs no longer have to go via OpenAIRE's aggregation.
RSpec.describe 'CBGP::Parsers.crossref_parser' do
  let(:crossref_body) do
    {
      message: {
        DOI: '10.1234/example',
        title: ['A Paper About Things'],
        'container-title': ['Journal of Things'],
        published: { 'date-parts': [[2024, 3, 15]] },
        author: [
          { given: 'María', family: 'García', ORCID: 'https://orcid.org/0000-0001-2345-6789' },
          { given: 'Jane', family: 'Outsider' } # no ORCID: a non-CBGP co-author
        ]
      }
    }.to_json
  end

  before do
    allow(RestClient).to receive(:get)
      .with('https://api.crossref.org/works/10.1234/example')
      .and_return(crossref_body)
  end

  it 'builds a publication Dataset with title, journal and date' do
    result = CBGP::Parsers.crossref_parser(doi: '10.1234/example')

    expect(result[:pub]).to be_a(CBGP::Dataset)
    expect(result[:pub].title).to eq('A Paper About Things')
    expect(result[:pub].journal).to eq('Journal of Things')
    expect(result[:pub].date).to eq('2024-03-15')
    expect(result[:pub].doi).to eq('10.1234/example')
  end

  it 'stores the full display-name author list on the dataset' do
    result = CBGP::Parsers.crossref_parser(doi: '10.1234/example')
    expect(result[:pub].authors).to eq(['María García', 'Jane Outsider'])
  end

  it 'returns the raw per-author given/family/ORCID alongside the dataset' do
    result = CBGP::Parsers.crossref_parser(doi: '10.1234/example')

    expect(result[:authors]).to eq([
                                      { name: 'María García', given: 'María', family: 'García', orcid: '0000-0001-2345-6789' },
                                      { name: 'Jane Outsider', given: 'Jane', family: 'Outsider', orcid: '' }
                                    ])
  end

  it 'returns pub: false when there is no container-title (journal)' do
    allow(RestClient).to receive(:get)
      .with('https://api.crossref.org/works/10.9999/no-journal')
      .and_return({ message: { title: ['x'] } }.to_json)

    result = CBGP::Parsers.crossref_parser(doi: '10.9999/no-journal')
    expect(result).to eq({ pub: false, authors: [] })
  end

  it 'returns pub: false without hammering the API on a persistent error' do
    allow(RestClient).to receive(:get).and_raise(RestClient::NotFound)

    result = CBGP::Parsers.crossref_parser(doi: '10.9999/gone')
    expect(result).to eq({ pub: false, authors: [] })
    expect(RestClient).to have_received(:get).at_most(2).times
  end
end
