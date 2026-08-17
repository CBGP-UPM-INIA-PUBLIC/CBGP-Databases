# frozen_string_literal: true

# Covers openaire_parser after it stopped discarding each creator's @orcid
# attribute (it used to keep only the bare display name). OpenAIRE rarely
# supplies an ORCID and never separate given/family parts, so this is the
# weakest of the three sources for personnel cross-referencing, but the data
# is used when present instead of being thrown away.
RSpec.describe 'CBGP::Parsers.openaire_parser' do
  let(:doi) { '10.1234/example' }
  let(:openaire_body) do
    {
      response: {
        results: {
          result: [
            {
              metadata: {
                'oaf:entity': {
                  'oaf:result': {
                    journal: { '$': 'Journal of Things' },
                    title: [{ '$': 'A Paper About Things' }],
                    creator: [
                      { '$': 'García M.', '@orcid': 'https://orcid.org/0000-0001-2345-6789' },
                      { '$': 'Outsider J.' }
                    ],
                    children: { result: [{ dateofacceptance: { '$': '2024-03-15T00:00:00Z' } }] },
                    originalId: [{ '$': doi }]
                  }
                }
              }
            }
          ]
        }
      }
    }.to_json
  end

  before do
    allow(RestClient).to receive(:get)
      .with("https://api.openaire.eu/search/publications?doi=#{doi}&format=json")
      .and_return(openaire_body)
  end

  it 'builds a publication Dataset with title, journal and date' do
    result = CBGP::Parsers.openaire_parser(doi: doi)

    expect(result[:pub]).to be_a(CBGP::Dataset)
    expect(result[:pub].title).to eq('A Paper About Things')
    expect(result[:pub].journal).to eq('Journal of Things')
    expect(result[:pub].date).to eq('2024-03-15')
  end

  it 'keeps each creator ORCID when OpenAIRE provides one, instead of discarding it' do
    result = CBGP::Parsers.openaire_parser(doi: doi)

    expect(result[:authors]).to eq([
                                      { name: 'García M.', given: nil, family: nil, orcid: '0000-0001-2345-6789' },
                                      { name: 'Outsider J.', given: nil, family: nil, orcid: '' }
                                    ])
  end

  it 'returns pub: false when the API call errors' do
    allow(RestClient).to receive(:get).and_raise(RestClient::NotFound)

    result = CBGP::Parsers.openaire_parser(doi: doi)
    expect(result).to eq({ pub: false, authors: [] })
  end
end
