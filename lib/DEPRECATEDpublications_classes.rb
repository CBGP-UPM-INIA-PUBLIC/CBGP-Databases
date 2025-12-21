require_relative 'queries'
require_relative 'core'
require_relative 'datacite_parser'
require_relative 'openaire_parser'

module CBGP
  class Publication
    attr_accessor :doi, :authors, :affiliations, :title, :journal, :volume, :date, :uniqid,
                  :cbgp_corresponding, :pubtype, :oa, :scopusq, :scopusd1, :sochoa

    def initialize(doi: '', authors: [], affiliations: [],
                   title: '', journal: '', date: '',
                   cbgp_corresponding: '', pubtype: '',
                   oa: '', scopusq: '', scopusd1: '', sochoa: '', uniqid: '')
      @doi = doi
      @authors = authors
      @affiliations = affiliations
      @title = title
      @journal = journal
      # @volume = volume
      @date = date
      @cbgp_corresponding = cbgp_corresponding
      @pubtype = pubtype
      @oa = oa
      @scopusq = scopusq
      @scopusd1 = scopusd1
      @sochoa = sochoa
      @uniqid = Time.now.to_i unless uniqid.match(/S/)
    end

    def self.load_from_params(params:)
      #  select ?g where {graph ?g {?pub sio:SIO_000671 ?id . ?id  sio:SIO_000300 "#{doi}" ;
      pub = CBGP::Parsers.params_parser_publication(params: params)
      res = retrieve_pub_graph_query(doi: pub.doi)
      oldgraphid = res.first[:g].to_s if res.first
      CBGP::Publication.write_to_db(pub: pub, oldid: oldgraphid)
      pub
    end

    def self.write_to_db(pub:, oldid: nil)
      warn 'WRITING PUBLICATION TO DB'
      write_pub_to_db_query(pub: pub, oldid: oldid)
    end
  end

  class Publication::Author
    attr_accessor :uniqueid, :name, :orcid, :rank

    def initialize(name: '', orcid: '', rank: 0)
      @name = name
      @orcid = orcid
      @rank = rank
      @uniqueid ||= Time.now.to_i
    end
  end
end
