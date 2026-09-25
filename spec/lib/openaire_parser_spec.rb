# frozen_string_literal: true

# Covers openaire_parser after a fix (found 2026-08-26 investigating why
# personnel cross-referencing never matched a real CBGP co-author on an
# OpenAIRE-sourced record): each creator record carries @name/@surname
# attributes alongside the "$" combined display string, but the parser used
# to read only "$", so given/family were always nil and the name-match
# fallback could never fire.
#
# @orcid is deliberately never populated here, even when OpenAIRE supplies
# one: per the user, OpenAIRE's author-disambiguation is algorithmic and
# less reliable than Crossref/DataCite (where ORCID is self-asserted), so a
# wrong OpenAIRE-supplied ORCID could cause a false match to the wrong CBGP
# member. Leaving orcid blank forces every OpenAIRE-sourced author through
# the name-match path instead, which resolves to the trustworthy,
# already-on-file member ORCID.
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
                      { '$': 'García, María', '@name': 'María', '@surname': 'García',
                        '@orcid': 'https://orcid.org/0000-0001-2345-678x' },
                      { '$': 'Outsider, Jane', '@name': 'Jane', '@surname': 'Outsider' }
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
    allow(CBGP::Parsers).to receive(:publication_type_answer_id).with('Article').and_return('ptype1')
  end

  it 'builds a publication Dataset with title, journal and date' do
    result = CBGP::Parsers.openaire_parser(doi: doi)

    expect(result[:pub]).to be_a(CBGP::Dataset)
    expect(result[:pub].title).to eq('A Paper About Things')
    expect(result[:pub].journal).to eq('Journal of Things')
    expect(result[:pub].date).to eq('2024-03-15')
  end

  it 'defaults publication_type to Article, since OpenAIRE has no reliable fine-grained type signal' do
    result = CBGP::Parsers.openaire_parser(doi: doi)
    expect(result[:pub].pubtype).to eq('ptype1')
  end

  it 'leaves open_access unset - OpenAIRE is never trusted for this, per the user (2026-08-26)' do
    result = CBGP::Parsers.openaire_parser(doi: doi)
    expect(result[:pub].oa).to be_nil
  end

  describe '#openaire_affiliations' do
    it 'only sets affiliations, never touches pub.oa (used to overwrite it from bestaccessright on every publication)' do
      pub = CBGP::Dataset.new(type: 'publication')
      pub.oa = 'oa_yes' # set by Crossref/DataCite upstream - must survive untouched

      CBGP::Parsers.openaire_affiliations(pub: pub, doi: doi)

      expect(pub.oa).to eq('oa_yes')
    end
  end

  it 'reads given/family from @name/@surname, but never trusts @orcid for matching' do
    result = CBGP::Parsers.openaire_parser(doi: doi)

    expect(result[:authors]).to eq([
                                      { name: 'García, María', given: 'María', family: 'García', orcid: '' },
                                      { name: 'Outsider, Jane', given: 'Jane', family: 'Outsider', orcid: '' }
                                    ])
  end

  it 'returns pub: false when the API call errors' do
    allow(RestClient).to receive(:get).and_raise(RestClient::NotFound)

    result = CBGP::Parsers.openaire_parser(doi: doi)
    expect(result).to eq({ pub: false, authors: [] })
  end
end
