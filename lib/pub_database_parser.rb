module CBGP
  class Parsers
    def self.publication_database_parser(doi:, graph:)

      core = retrieve_publication_core_query(doi: doi, graph: graph)
      auths = retrieve_publication_auths_query(doi: doi, graph: graph)
      affils = retrieve_publication_affils_query(doi: doi, graph: graph)

      journal = jpath.on(dcite).first
      return false if journal.empty?

      affiliations = []

      title = jpath.on(dcite).first

      authors = []
        aut = CBGP::Publication::Author.new(name: "#{author['given']} #{author['family']}", orcid: orcid,
                                            rank: _index)
        authors << aut
      end

      date = results[0..9] # comes back as dateand time

      doi = jpath.on(dcite).first
      volume = jpath.on(dcite).first
      pages = jpath.on(dcite).first
      startpage = pages
      endpage = pages

      # cbgp_corresponding: '',
      # pubtype: '',
      # oa: '',
      # scopusq: '',
      # scopusd1: '',
      # sochoa: ''

      full_ref = "#{journal} #{volume} (#{date}) pp#{startpage}-#{endpage}"
      warn "FULL REF", full_ref, "\n\n"

      pub = CBGP::Publication.new(
        doi: doi,
        authors: [authors], # make it a list of lists so that only one instance is sent to the widget
        affiliations: [affiliations],
        title: title,
        journal: journal,
        full_ref: full_ref,
        date: date,
        cbgp_corresponding: '',
        pubtype: '',
        oa: '',
        scopusq: '',
        scopusd1: '',
        sochoa: ''
      )
# abort "affiliations #{affiliations.inspect} pub: #{pub.affiliations}"
      # warn "PUB = #{pub.inspect}"
      pub
    end
  end
end
