module CBGP
  class Parsers
    def self.publication_database_parser(doi:, graph:)

      core = retrieve_publication_core_query(doi: doi, graph: graph)
      #   ?doi ?scopusq ?scopusd1 ?oa ?sochoa ?pubtype ?title ?date ?journal ?volume

      auths = retrieve_publication_auths_query(doi: doi, graph: graph)
      affils = retrieve_publication_affils_query(doi: doi, graph: graph)

      journal = core.first[:journal].to_s
      return false if journal.to_s.empty?

      title = core.first[:title].to_s
      date = core.first[:date].to_s
      doi = core.first[:doi].to_s
      volume = core.first[:volume].to_s
      cbgp_corresponding = core.first[:cbgp_corresponding].to_s
      pubtype = core.first[:pubtype].to_s
      oa = core.first[:oa].to_s
      scopusq = core.first[:scopusq].to_s
      scopusd1 = core.first[:scopusd1].to_s
      sochoa = core.first[:sochoa].to_s

      startpage = "0"
      endpage = "0"



      affiliations = []
      affils.each do |res|
        affil = res[:affiliation].to_s
        affiliations << affil
      end
# abort "got affiliations #{affiliations}"

      authors = []
      auths.each do |res|
        aut = CBGP::Publication::Author.new(name: res[:name].to_s, orcid: res[:orcid].to_s,
                                            rank: res[:rank].to_s)
        authors << aut
      end
# abort "got authors #{authors}"

      # abort "successful completion of parse from database"
      pub = CBGP::Publication.new(
        doi: doi,
        authors: [authors], # make it a list of lists so that only one instance is sent to the widget
        affiliations: [affiliations],
        title: title,
        journal: journal,
        date: date,
        cbgp_corresponding: cbgp_corresponding,
        pubtype: pubtype,
        oa: oa,
        scopusq: scopusq,
        scopusd1: scopusd1,
        sochoa: sochoa
      )

      pub
    end
  end
end
