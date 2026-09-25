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

  it 'builds a publication Dataset with title, journal, date and doi' do
    result = CBGP::Parsers.datacite_parser(doi: '10.1234/example')

    expect(result[:pub]).to be_a(CBGP::Dataset)
    expect(result[:pub].title).to eq('A Paper About Things')
    expect(result[:pub].journal).to eq('Journal of Things')
    expect(result[:pub].date).to eq('2024-03-15')
    expect(result[:pub].doi).to eq('10.1234/example')
    expect(result[:pub].pubtype).to eq('ptype1') # no "type" in the fixture -> defaults to Article
    expect(result[:pub].oa).to eq('') # no "copyright" in the fixture -> left unset
  end

  it 'sets open_access to "Yes" from an open copyright string' do
    allow(RestClient).to receive(:get)
      .with('https://doi.org/10.9999/open-example', anything)
      .and_return({ title: 'x', DOI: '10.9999/open-example', copyright: 'Creative Commons Attribution 4.0 International' }.to_json)

    result = CBGP::Parsers.datacite_parser(doi: '10.9999/open-example')
    expect(result[:pub].oa).to eq('oa_yes')
  end

  it 'classifies a book/chapter deposit from the CSL-JSON "type" field' do
    allow(RestClient).to receive(:get)
      .with('https://doi.org/10.9999/a-chapter', anything)
      .and_return({ title: 'A Chapter', DOI: '10.9999/a-chapter', type: 'chapter' }.to_json)

    result = CBGP::Parsers.datacite_parser(doi: '10.9999/a-chapter')
    expect(result[:pub].pubtype).to eq('ptype2')
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

  it 'still succeeds with an empty journal when there is no container-title (a dataset/software deposit)' do
    # DataCite covers non-journal deposits too (datasets, software - e.g. a
    # real Zenodo record, 10.5281/zenodo.1065973, found 2026-08-26) which
    # legitimately have no journal. Gating validity on journal presence used
    # to silently reject every one of these.
    allow(RestClient).to receive(:get)
      .with('https://doi.org/10.9999/no-journal', anything)
      .and_return({ title: 'x', DOI: '10.9999/no-journal' }.to_json)

    result = CBGP::Parsers.datacite_parser(doi: '10.9999/no-journal')
    expect(result[:pub]).to be_a(CBGP::Dataset)
    expect(result[:pub].journal).to eq('')
  end

  it 'returns pub: false when there is no title at all' do
    allow(RestClient).to receive(:get)
      .with('https://doi.org/10.9999/no-title', anything)
      .and_return({ DOI: '10.9999/no-title' }.to_json)

    result = CBGP::Parsers.datacite_parser(doi: '10.9999/no-title')
    expect(result).to eq({ pub: false, authors: [] })
  end
end
