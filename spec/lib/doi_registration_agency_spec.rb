# frozen_string_literal: true

# Covers resolve_doi_registration_agency, ported from
# FAIRChampionHarvester::DOI (fair_champion_harvester gem, used by
# Community-FAIR-Tests) rather than taken on as a dependency - see
# lib/doi_registration_agency.rb for why. This is what lib/loaders.rb uses to
# pick datacite_parser vs. crossref_parser instead of blindly trying one and
# retrying on failure.
RSpec.describe 'CBGP::Parsers.resolve_doi_registration_agency' do
  it 'returns the RA field from the doi.org/doiRA/ response' do
    allow(RestClient).to receive(:get)
      .with('https://doi.org/doiRA/10.1234/example')
      .and_return('[{"DOI":"10.1234/example","RA":"DataCite"}]')

    expect(CBGP::Parsers.resolve_doi_registration_agency(doi: '10.1234/example')).to eq('DataCite')
  end

  it 'strips a leading https://doi.org/ prefix and downcases before querying' do
    allow(RestClient).to receive(:get)
      .with('https://doi.org/doiRA/10.1234/example')
      .and_return('[{"DOI":"10.1234/example","RA":"Crossref"}]')

    result = CBGP::Parsers.resolve_doi_registration_agency(doi: 'https://doi.org/10.1234/EXAMPLE')
    expect(result).to eq('Crossref')
  end

  it 'returns false when the DOI is blank' do
    expect(CBGP::Parsers.resolve_doi_registration_agency(doi: '')).to eq(false)
  end

  it 'returns false when the resolution service errors' do
    allow(RestClient).to receive(:get).and_raise(RestClient::NotFound)

    expect(CBGP::Parsers.resolve_doi_registration_agency(doi: '10.1234/missing')).to eq(false)
  end

  it 'returns false when the response is not valid JSON' do
    allow(RestClient).to receive(:get).and_return('not json')

    expect(CBGP::Parsers.resolve_doi_registration_agency(doi: '10.1234/broken')).to eq(false)
  end
end
