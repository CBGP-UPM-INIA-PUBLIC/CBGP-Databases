require 'json'

module CBGP
  class Parsers
    # Resolves which registration agency (e.g. "DataCite", "Crossref") issued a
    # DOI, using the official https://doi.org/doiRA/ resolution service.
    #
    # Ported (not required as a gem dependency) from
    # FAIRChampionHarvester::DOI.resolve_doi_to_registration_agency in the
    # fair_champion_harvester gem, used by the Community-FAIR-Tests project.
    # This project only has this one DOI-metadata use case, so duplicating the
    # ~15 lines here was preferred over taking on the whole harvester gem as a
    # dependency. If this logic needs to change, consider upstreaming the fix
    # into fair_champion_harvester too, since it started life there.
    #
    # @param doi [String]
    # @return [String, false] the registration agency name (e.g. "DataCite",
    #   "Crossref"), or +false+ if it can't be resolved
    def self.resolve_doi_registration_agency(doi:)
      clean_doi = doi.to_s.strip.downcase.sub(%r{^https?://doi\.org/}, '')
      return false if clean_doi.empty?

      url = "https://doi.org/doiRA/#{clean_doi}"
      warn "Resolving registration agency for #{clean_doi} via #{url}"

      begin
        body = RestClient.get(url)
        json = JSON.parse(body)
        json.dig(0, 'RA')
      rescue StandardError => e
        warn "Could not resolve registration agency for #{clean_doi}: #{e.inspect}"
        false
      end
    end
  end
end
