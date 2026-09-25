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
    # publication_type_answer_id normally resolves against the live ontology
    # (see publication_type_classifier_spec.rb for that in isolation) -
    # stubbed here to the real "Article"/"Book" -> "ptype1"/"ptype2" mapping
    # so these specs stay offline/hermetic while still covering the wiring.
    allow(CBGP::Parsers).to receive(:publication_type_answer_id) do |label|
      { 'Article' => 'ptype1', 'Book' => 'ptype2' }[label]
    end
    # open_access_answer_id normally resolves against the live ontology (see
    # open_access_classifier_spec.rb for that in isolation) - stubbed here
    # to the real "Yes"/"No" -> "oa_yes"/"oa_no" mapping so these specs stay
    # offline/hermetic while still covering the wiring.
    allow(CBGP::Parsers).to receive(:open_access_answer_id) do |label|
      { 'Yes' => 'oa_yes', 'No' => 'oa_no' }[label]
    end
  end

  it 'builds a publication Dataset with title, journal and date' do
    result = CBGP::Parsers.crossref_parser(doi: '10.1234/example')

    expect(result[:pub]).to be_a(CBGP::Dataset)
    expect(result[:pub].title).to eq('A Paper About Things')
    expect(result[:pub].journal).to eq('Journal of Things')
    expect(result[:pub].date).to eq('2024-03-15')
    expect(result[:pub].doi).to eq('10.1234/example')
    expect(result[:pub].pubtype).to eq('ptype1') # no "type" in the fixture -> defaults to Article
    expect(result[:pub].oa).to eq('') # no "license" in the fixture -> left unset
  end

  it 'sets open_access to "Yes" for an open-license entry with no embargo' do
    allow(RestClient).to receive(:get)
      .with('https://api.crossref.org/works/10.9999/open-example')
      .and_return({ message: { DOI: '10.9999/open-example', title: ['x'],
                                license: [{ URL: 'https://creativecommons.org/licenses/by/4.0', 'delay-in-days': 0 }] } }.to_json)

    result = CBGP::Parsers.crossref_parser(doi: '10.9999/open-example')
    expect(result[:pub].oa).to eq('oa_yes')
  end

  it 'leaves open_access unset (not "No") for an embargoed or non-open license' do
    allow(RestClient).to receive(:get)
      .with('https://api.crossref.org/works/10.9999/embargoed-example')
      .and_return({ message: { DOI: '10.9999/embargoed-example', title: ['x'],
                                license: [{ URL: 'https://creativecommons.org/licenses/by/4.0', 'delay-in-days': 365 }] } }.to_json)

    result = CBGP::Parsers.crossref_parser(doi: '10.9999/embargoed-example')
    expect(result[:pub].oa).to eq('')
  end

  it 'classifies a book chapter from the Crossref "type" field (real example: 10.1142/9789811265679_0033)' do
    allow(RestClient).to receive(:get)
      .with('https://api.crossref.org/works/10.1142/9789811265679_0033')
      .and_return({ message: { DOI: '10.1142/9789811265679_0033', title: ['A Chapter'], type: 'book-chapter' } }.to_json)

    result = CBGP::Parsers.crossref_parser(doi: '10.1142/9789811265679_0033')
    expect(result[:pub].pubtype).to eq('ptype2')
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

  it 'falls back to the posting institution when there is no container-title (a preprint)' do
    # bioRxiv/medRxiv "posted-content" records have no journal at all - real
    # example (10.1101/418376) found 2026-08-26: crossref_parser used to
    # reject every preprint outright by requiring a journal name, which
    # silently discarded genuinely valid Crossref records.
    allow(RestClient).to receive(:get)
      .with('https://api.crossref.org/works/10.1101/preprint-example')
      .and_return({ message: { DOI: '10.1101/preprint-example', title: ['A Preprint'],
                                institution: [{ name: 'bioRxiv' }] } }.to_json)

    result = CBGP::Parsers.crossref_parser(doi: '10.1101/preprint-example')
    expect(result[:pub]).to be_a(CBGP::Dataset)
    expect(result[:pub].journal).to eq('bioRxiv')
  end

  it 'falls back to an empty journal when neither container-title nor institution is present' do
    allow(RestClient).to receive(:get)
      .with('https://api.crossref.org/works/10.9999/no-journal')
      .and_return({ message: { DOI: '10.9999/no-journal', title: ['x'] } }.to_json)

    result = CBGP::Parsers.crossref_parser(doi: '10.9999/no-journal')
    expect(result[:pub]).to be_a(CBGP::Dataset)
    expect(result[:pub].journal).to eq('')
  end

  it 'returns pub: false when there is no title at all' do
    allow(RestClient).to receive(:get)
      .with('https://api.crossref.org/works/10.9999/no-title')
      .and_return({ message: { DOI: '10.9999/no-title' } }.to_json)

    result = CBGP::Parsers.crossref_parser(doi: '10.9999/no-title')
    expect(result).to eq({ pub: false, authors: [] })
  end

  it 'returns pub: false without hammering the API on a persistent error' do
    allow(RestClient).to receive(:get).and_raise(RestClient::NotFound)

    result = CBGP::Parsers.crossref_parser(doi: '10.9999/gone')
    expect(result).to eq({ pub: false, authors: [] })
    expect(RestClient).to have_received(:get).at_most(2).times
  end
end
