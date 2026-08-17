module CBGP
  class Loaders
    # Public: Load a single DOI (existing behavior preserved)
    def self.load_doi(doi:, database: 'publication')
      messages = []
      # allpubs  = []

      warn "\n\n\nFETCHING DOI #{doi}\n\n\n"
      result = load_or_fetch_doi(doi: doi, database: database)

      if result[:existing]
        warn "DOI #{doi} already exists in database"
        messages << "DOI:#{doi} was already in database"

      elsif result[:pub]
        warn "Loaded and saved new publication for DOI #{doi}"
        messages << "DOI:#{doi} loaded and saved successfully"
      else
        warn "Failed to load DOI #{doi}"
        messages << "Failed to load DOI:#{doi}"
      end

      result[:pub] # Return the Dataset object (or nil)
    end

    # Public: Bulk load multiple DOIs
    def self.bulk_load_from_dois(dois:, database: 'publication')
      messages = []
      allpubs  = []

      normalized_dois = dois.to_s.split(/[, \t\n]+/).map(&:strip).reject(&:empty?).uniq

      normalized_dois.each do |doi|
        warn "\n\n\nFETCHING DOI #{doi}\n\n\n"
        result = load_or_fetch_doi(doi: doi, database: database)

        if result[:existing]
          messages << "DOI:#{doi} was already in database"
        elsif result[:pub]
          allpubs << result[:pub]
          messages << "DOI:#{doi} loaded and saved successfully"
        else
          messages << "Failed to load DOI:#{doi}"
        end
      end

      messages << 'No errors encountered during upload' if messages.none? { |m| m.include?('Failed') }

      [allpubs, messages]
    end

    private

    # Shared core logic: check existence → parse if new → write
    def self.load_or_fetch_doi(doi:, database:)
      # 1. Check if already exists
      graphs = execute_search(search_params: { 'newpub4' => doi }, dataset_type: database)

      if graphs&.any?
        graph = graphs.first
        warn "Found existing graph for DOI #{doi}: #{graph}"
        pub = CBGP::Dataset.load_from_graph(graph: graph, database: database)
        return { pub: pub, existing: true }
      end

      # 2. Not found → parse. Ask doi.org which agency registered this DOI so
      # we go straight to the richest matching source instead of guessing:
      # DataCite-registered DOIs go to datacite_parser, Crossref-registered
      # ones to crossref_parser. OpenAIRE aggregates both (and more), so it
      # remains the fallback when the agency is unknown or the preferred
      # parser comes back empty.
      agency = CBGP::Parsers.resolve_doi_registration_agency(doi: doi)
      result = case agency
               when 'DataCite'
                 CBGP::Parsers.datacite_parser(doi: doi)
               when 'Crossref'
                 CBGP::Parsers.crossref_parser(doi: doi)
               else
                 { pub: false, authors: [] }
               end

      result = CBGP::Parsers.openaire_parser(doi: doi) unless result[:pub]

      pub = result[:pub]
      return { pub: nil, existing: false } unless pub

      # enrich affiliations regardless of which parser found the core record
      CBGP::Parsers.openaire_affiliations(pub: pub, doi: doi)

      # Cross-reference authors against existing CBGP personnel by ORCID (when
      # the source gave us one) or exact accent-insensitive name match
      # otherwise - never fuzzy, to avoid mis-attributing an outside
      # co-author's identity to a CBGP member.
      matched_orcids = CBGP::Parsers.match_authors_to_personnel(authors: result[:authors])
      pub.cbgp_author_orcids = matched_orcids if pub.respond_to?(:cbgp_author_orcids=)

      # 3. Save it
      pub.write_to_db
      { pub: pub, existing: false }
    end
  end
end
