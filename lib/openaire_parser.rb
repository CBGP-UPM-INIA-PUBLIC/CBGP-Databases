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

      # OpenAIRE's creator records carry a bare display name (e.g. "Smith
      # J."), not separate given/family parts, and rarely an ORCID (@orcid
      # attribute) - so raw_authors here is the weakest of the three sources
      # for personnel cross-referencing, but still worth trying.
      raw_authors = []
      names_only = []
      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].creator[*]')
      results = jpath.on(oaire)
      results.each do |author|
        aname = Sanitize.fragment(author['$'])
        orcid = author['@orcid'].to_s.gsub(%r{https?://orcid.org/}, '')
        orcid = Sanitize.fragment(orcid)
        raw_authors << { name: aname, given: nil, family: nil, orcid: orcid }
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

      { pub: dataset, authors: raw_authors }
    end

    def self.openaire_affiliations(pub:, doi:) # rubocop:disable Metrics/MethodLength
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
      pub.oa = get_os_from_doi_json(json: oaire)
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

    def self.get_os_from_doi_json(json:)
      oa = ''
      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].bestaccessright["@classid"]')
      result = jpath.on(json)
      oa = 'Yes' if result.first == 'OPEN'
      oa
    end
  end
end
