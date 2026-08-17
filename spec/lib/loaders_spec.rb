# frozen_string_literal: true

# Covers CBGP::Loaders.load_or_fetch_doi's orchestration after the redesign:
#  - resolves the DOI's registration agency first and dispatches straight to
#    datacite_parser/crossref_parser instead of blindly trying one then
#    catching+retrying (see lib/doi_registration_agency.rb);
#  - falls back to openaire_parser when the agency is unknown or the
#    preferred parser comes back empty;
#  - runs the new personnel cross-reference step and stores matched ORCIDs on
#    publication_cbgp_authors before saving.
RSpec.describe 'CBGP::Loaders.load_or_fetch_doi' do
  let(:doi) { '10.1234/example' }
  let(:pub) { CBGP::Dataset.new(type: 'publication') }

  before do
    allow(pub).to receive(:write_to_db)
    allow(CBGP::Parsers).to receive(:openaire_affiliations).with(hash_including(pub: pub, doi: doi))
  end

  context 'when a graph for this DOI already exists' do
    it 'loads and returns the existing record without calling any parser or the agency lookup' do
      allow(CBGP::Loaders).to receive(:execute_search)
        .with(hash_including(search_params: { 'newpub4' => doi }))
        .and_return(['graph://existing'])
      allow(CBGP::Dataset).to receive(:load_from_graph)
        .with(hash_including(graph: 'graph://existing'))
        .and_return(pub)

      expect(CBGP::Parsers).not_to receive(:resolve_doi_registration_agency)

      result = CBGP::Loaders.load_or_fetch_doi(doi: doi, database: 'publication')
      expect(result).to eq({ pub: pub, existing: true })
    end
  end

  context 'when the DOI is not yet in the database' do
    before do
      allow(CBGP::Loaders).to receive(:execute_search)
        .with(hash_including(search_params: { 'newpub4' => doi }))
        .and_return([])
      allow(CBGP::Parsers).to receive(:match_authors_to_personnel).and_return([])
    end

    it 'dispatches DataCite-registered DOIs straight to datacite_parser' do
      allow(CBGP::Parsers).to receive(:resolve_doi_registration_agency).with(hash_including(doi: doi)).and_return('DataCite')
      expect(CBGP::Parsers).to receive(:datacite_parser).with(hash_including(doi: doi)).and_return({ pub: pub, authors: [] })
      expect(CBGP::Parsers).not_to receive(:crossref_parser)
      expect(CBGP::Parsers).not_to receive(:openaire_parser)

      CBGP::Loaders.load_or_fetch_doi(doi: doi, database: 'publication')
    end

    it 'dispatches Crossref-registered DOIs straight to crossref_parser' do
      allow(CBGP::Parsers).to receive(:resolve_doi_registration_agency).with(hash_including(doi: doi)).and_return('Crossref')
      expect(CBGP::Parsers).to receive(:crossref_parser).with(hash_including(doi: doi)).and_return({ pub: pub, authors: [] })
      expect(CBGP::Parsers).not_to receive(:datacite_parser)

      CBGP::Loaders.load_or_fetch_doi(doi: doi, database: 'publication')
    end

    it 'falls back to openaire_parser when the agency is unknown' do
      allow(CBGP::Parsers).to receive(:resolve_doi_registration_agency).with(hash_including(doi: doi)).and_return(false)
      expect(CBGP::Parsers).to receive(:openaire_parser).with(hash_including(doi: doi)).and_return({ pub: pub, authors: [] })

      CBGP::Loaders.load_or_fetch_doi(doi: doi, database: 'publication')
    end

    it 'falls back to openaire_parser when the preferred parser comes back empty' do
      allow(CBGP::Parsers).to receive(:resolve_doi_registration_agency).with(hash_including(doi: doi)).and_return('DataCite')
      allow(CBGP::Parsers).to receive(:datacite_parser).with(hash_including(doi: doi)).and_return({ pub: false, authors: [] })
      expect(CBGP::Parsers).to receive(:openaire_parser).with(hash_including(doi: doi)).and_return({ pub: pub, authors: [] })

      CBGP::Loaders.load_or_fetch_doi(doi: doi, database: 'publication')
    end

    it 'returns pub: nil without saving when every parser fails' do
      allow(CBGP::Parsers).to receive(:resolve_doi_registration_agency).with(hash_including(doi: doi)).and_return(false)
      allow(CBGP::Parsers).to receive(:openaire_parser).with(hash_including(doi: doi)).and_return({ pub: false, authors: [] })

      result = CBGP::Loaders.load_or_fetch_doi(doi: doi, database: 'publication')
      expect(result).to eq({ pub: nil, existing: false })
      expect(pub).not_to have_received(:write_to_db)
    end

    it 'sets cbgp_author_orcids from the personnel matcher and saves before returning' do
      allow(CBGP::Parsers).to receive(:resolve_doi_registration_agency).with(hash_including(doi: doi)).and_return('DataCite')
      raw_authors = [{ name: 'María García', given: 'María', family: 'García', orcid: '0000-0001-2345-6789' }]
      allow(CBGP::Parsers).to receive(:datacite_parser).with(hash_including(doi: doi)).and_return({ pub: pub, authors: raw_authors })
      allow(CBGP::Parsers).to receive(:match_authors_to_personnel)
        .with(hash_including(authors: raw_authors))
        .and_return(['0000-0001-2345-6789'])

      result = CBGP::Loaders.load_or_fetch_doi(doi: doi, database: 'publication')

      expect(pub.cbgp_author_orcids).to eq(['0000-0001-2345-6789'])
      expect(pub).to have_received(:write_to_db)
      expect(result).to eq({ pub: pub, existing: false })
    end
  end
end
