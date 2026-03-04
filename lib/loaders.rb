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

      # 2. Not found → try to parse
      pub = CBGP::Parsers.datacite_parser(doi: doi) # returns false on fail

      if pub
        # enrich affiliations
        CBGP::Parsers.openaire_affiliations(pub: pub, doi: doi)
      else
        # Fallback to openaire full parse
        pub = CBGP::Parsers.openaire_parser(doi: doi)
      end

      # 3. If we got something, save it
      if pub
        pub.write_to_db
        { pub: pub, existing: false }
      else
        { pub: nil, existing: false }
      end
    end
  end
end
