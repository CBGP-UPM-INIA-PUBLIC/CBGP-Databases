module CBGP
  class Loaders
    def self.load_doi(doi:, database: 'publications')
      # hard code DOI field... ugh!   TODO stop this!
      res = execute_search(search_params: { 'newpub4' => doi }, dataset_type: database) # Return array of graph URIs
      # warn "found record from doi", res.inspect
      # abort "graph query failed" unless res.first
      graph = res.first if res
      # record = CBGP::Dataset.new(type: database )

      if graph
        warn "\n \nretrieving from database\n\n"
        pub = CBGP::Dataset.load_from_graph(graph: graph, database: database)
      else
        pub = CBGP::Parsers.datacite_parser(doi: doi)
        pub = if pub
                CBGP::Parsers.openaire_affiliations(pub: pub, doi: doi) # fill-in affiliations only
              else
                CBGP::Parsers.openaire_parser(doi: doi)
              end
        pub.write_to_db #
      end
      pub
    end

    def self.bulk_load_from_dois(dois:, database: 'publications')
      messages = []
      allpubs = []
      alldois = dois.split(/[, \t\n]+/).map(&:strip).reject(&:empty?) # accept both comma-separated and newline separated
      alldois.each do |doi|
        res = execute_search(search_params: { 'newpub4' => doi }, dataset_type: database) # Return array of graph URIs
        # warn "found record from doi", res.inspect
        # abort "graph query failed" unless res.first
        graph = res.first if res
        # record = CBGP::Dataset.new(type: database )

        if graph
          messages << "DOI:#{doi} was already in database\n"
        else
          pub = CBGP::Parsers.datacite_parser(doi: doi)
          pub = if pub
                  CBGP::Parsers.openaire_affiliations(pub: pub, doi: doi) # fill-in affiliations only
                else
                  CBGP::Parsers.openaire_parser(doi: doi)
                end
          pub.write_to_db
          allpubs << pub
        end
      end
      messages << 'No errors Encountered During Upload' unless messages.first
      [allpubs, messages]
    end
  end
end
