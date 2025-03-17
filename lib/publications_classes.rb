require_relative 'queries'
require_relative 'core'
require_relative 'datacite_parser'
require_relative 'openaire_parser'

# REQUIREMENTS:

# FULL PUBLICATION INFO – example: Taguas, I., Maclot, F., Montes, N., Pagán, I., Fraile, A., García-Arenal, F. 2025. Infection Patterns of Albugo laibachii and Effect on Host Survival and Reproduction in a Wild Population of Arabidopsis thaliana. Plants 14, 568. DOI: 10.3390/plants14040568
# CORRESPONDING CBGP AUTHOR – Is the corresponding author from CBGP, yes or no
# DOI NR
# JOURNAL NAME
# TITLE OF THE PUBLICATION
# TYPE (ARTICLE, BOOK)
# OPEN-ACCESS ARTICLE (YES/NO)
# DATE OF PUBLICATION
# Scopus Q (Q1,Q2,Q3,Q4)
# SCOPUS D1 (YES/NO)
# SO acknowledgment - IS THERE SEVERO OCHOA ACKONWLEDGEMENT IN THE PUBLICATION? YES/NO


module CBGP

  class Publication
    attr_accessor :doi, :authors, :affiliations, :title, :journal, :volume, :full_ref 
    attr_accessor :date, :uniqid, :cbgp_corresponding
    attr_accessor :pubtype, :oa, :scopusq, :scopusd1, :sochoa

    def initialize(doi: '', authors: [[]], affiliations: [[]], 
                  title: '', journal: '', full_ref: '', date: '', 
                  cbgp_corresponding: "No", pubtype: "", 
                  oa: "No", scopusq: "", scopusd1: "", sochoa: "No", uniqid: '')

      @doi = doi
      @authors = authors
      @affiliations = affiliations
      @title = title
      @journal = journal
      @full_ref = full_ref
      @volume = volume
      @date = date
      @cbgp_corresponding = cbgp_corresponding
      @pubtype = pubtype
      @oa = oa
      @scopusq = scopusq
      @scopusd1 = scopusd1
      @sochoa = sochoa
      @uniqid = Time.now.to_i unless uniqid.match(/S/)
    end

    
    def self.load_from_doi(doi:)

      res = retrieve_pub_graph_query(doi: doi)
      # abort "graph query failed" unless res.first
      if res.first
        pub = CBGP::Parsers.publication_database_parser(doi: doi, graph: res.first[:g])
      else
        # need to check database one day!
        pub = CBGP::Parsers.datacite_parser(doi: doi)
        if pub
          pub = CBGP::Parsers.openaire_affiliations(pub: pub, doi: doi)  # fill-in affiliations only
        else
          pub = CBGP::Parsers.openaire_parser(doi: doi)
        end
        CBGP::Publication.write_to_db(pub: pub)
      end
      return pub
    end

    def self.write_to_db(pub:)
      write_pub_to_db_query(pub: pub)
    end

  end


  class Publication::Author
    attr_accessor :uniqueid, :name, :orcid, :rank
    def initialize(name:, orcid: "", rank: 0)
      @name = name
      @orcid = orcid
      @rank = rank
      @uniqueid = Time.now.to_i unless @uniqueid
    end
  end

end
