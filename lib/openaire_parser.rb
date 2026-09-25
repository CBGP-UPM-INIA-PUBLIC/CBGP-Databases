module CBGP
  class Parsers
    def self.openaire_parser(doi:)
      begin
        # abort
        warn "https://api.openaire.eu/search/publications?doi=#{doi}&format=json"
        json = RestClient.get("https://api.openaire.eu/search/publications?doi=#{doi}&format=json")
        oaire = JSON.parse(json)
      rescue StandardError => e
        warn "openaire error #{e.inspect}"
        return { pub: false, authors: [] }
      end

      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].journal.$')
      journal = jpath.on(oaire).first
      journal = Sanitize.fragment(journal.to_s)

      return { pub: false, authors: [] } if journal.empty?

      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].title[0].$')
      title = jpath.on(oaire).first
      title = Sanitize.fragment(title.to_s)

      # Each creator record carries @name (given) and @surname (family)
      # attributes alongside the "$" combined display string - found
      # 2026-08-26 while investigating why personnel cross-referencing never
      # matched a real CBGP co-author on an OpenAIRE-sourced record: the
      # parser only ever read the combined "$" string, never @name/@surname,
      # so match_authors_to_personnel's name-match fallback (which needs
      # given/family separately) could never fire.
      #
      # @orcid is deliberately NOT used for matching (per the user, 2026-08-26):
      # OpenAIRE's author-disambiguation is algorithmic/aggregated and less
      # reliable than Crossref/DataCite, where the ORCID is typically
      # self-asserted - a wrong OpenAIRE-supplied ORCID could otherwise cause
      # a false match to the wrong CBGP member. match_authors_to_personnel
      # tries ORCID first, then falls back to a name match, so leaving orcid
      # blank here forces every OpenAIRE-sourced author through the (still
      # trustworthy) name-match path, which resolves to the member's own
      # on-file ORCID, not OpenAIRE's guess.
      raw_authors = []
      names_only = []
      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].creator[*]')
      results = jpath.on(oaire)
      results.each do |author|
        aname = Sanitize.fragment(author['$'])
        given = Sanitize.fragment(author['@name'].to_s)
        family = Sanitize.fragment(author['@surname'].to_s)
        raw_authors << { name: aname, given: given, family: family, orcid: '' }
        names_only << aname
      end

      date = '' #      response.results.result[0].metadata["oaf:entity"]["oaf:result"].children.result[1].dateofacceptance
      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].children.result[*]')
      results = jpath.on(oaire)
      results.each_with_index do |entity, _index|
        next unless entity['dateofacceptance']

        date = entity['dateofacceptance']['$']
        date = date[0..9] # cut off the zenith time
        warn 'OADATE', date, "\n\n"
      end

      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].journal["@vol"]')
      _volume = jpath.on(oaire)

      # OpenAPIRE graph doesn't capture this!
      # issue = ''
      # path = JsonPath.new('')
      # issue = jpath.on(oaire)

      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].journal["@sp"]')
      _startpage = jpath.on(oaire)

      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].journal["@ep"]')
      _endpage = jpath.on(oaire)

      dataset = CBGP::Dataset.new(type: 'publication')

      dataset.doi = doi
      dataset.authors = names_only # make it a list of lists so that only one instance is sent to the widget
      dataset.affiliations = get_affiliation_from_doi_json(json: oaire)
      dataset.title = title
      dataset.journal = journal
      dataset.date = date
      # OpenAIRE's "resulttype" only distinguishes publication/dataset/
      # software - not article vs. book - so there's no reliable per-record
      # signal here (unlike Crossref/DataCite, see
      # lib/publication_type_classifier.rb). Defaults to "Article", true for
      # the vast majority of CBGP publications, rather than leaving it unset.
      dataset.pubtype = publication_type_answer_id('Article')
      # publication_open_access is deliberately left unset here (per the
      # user, 2026-08-26): OpenAIRE's bestaccessright classification is not
      # trusted for this at all, only Crossref/DataCite's own license data
      # (see lib/open_access_classifier.rb) - and this openaire_parser path
      # only ever runs when neither of those could resolve the record in the
      # first place, so there's no better signal available anyway.

      { pub: dataset, authors: raw_authors }
    end

    def self.openaire_affiliations(pub:, doi:)
      begin
        # abort
        warn "https://api.openaire.eu/search/publications?doi=#{doi}&format=json"
        json = RestClient.get("https://api.openaire.eu/search/publications?doi=#{doi}&format=json")
        oaire = JSON.parse(json)
      rescue StandardError => e
        warn "error #{e.inspect}"
        return false
      end
      pub.affiliations = get_affiliation_from_doi_json(json: oaire)
      # Used to also set pub.oa from OpenAIRE's bestaccessright here - this
      # ran unconditionally on EVERY publication regardless of which parser
      # built it, silently overwriting whatever Crossref/DataCite had
      # already determined (see lib/open_access_classifier.rb). Removed per
      # the user, 2026-08-26: OpenAIRE is not trusted for open-access status
      # at all.
      pub
    end

    def self.get_affiliation_from_doi_json(json:)
      affiliations = []
      # Define the JSONPath query with a wildcard to match all "rel" elements
      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].rels.rel[*].legalname.$') # the affiliation name
      # Execute the query and get all matches
      results = jpath.on(json)
      # Loop through the results and print each legalname
      results.each_with_index do |legalname, index|
        puts "rel[#{index}].legalname: #{legalname}"
        affiliations << legalname unless affiliations.include? legalname
      end
      affiliations
    end
  end
end
