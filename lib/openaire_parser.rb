module CBGP
  class Parsers
    def self.openaire_parser(doi:)
      begin
        # abort
        warn "https://api.openaire.eu/search/publications?doi=#{doi}&format=json"
        json = RestClient.get("https://api.openaire.eu/search/publications?doi=#{doi}&format=json")
        oaire = JSON.parse(json)
      rescue StandardError => e
        warn "error #{e.inspect}"
        return false
      end

      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].journal.$')
      journal = jpath.on(oaire)
      journal = Sanitize.fragment(journal)

      return false if journal.empty?

      affiliations = []
      # Define the JSONPath query with a wildcard to match all "rel" elements
      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].rels.rel[*].legalname.$') # the affiliation name
      # jpath = JsonPath.new('$["response"]["results"]["result"][0]["metadata"]["oaf:entity"]["oaf:result"]["rels"]["rel"][*]["legalname"]')
      # Execute the query and get all matches
      results = jpath.on(oaire)
      # Loop through the results and print each legalname
      results.each_with_index do |legalname, index|
        # puts "rel[#{index}].legalname: #{legalname}"
        legalname = Sanitize.fragment(legalname)
        affiliations << legalname
      end

      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].title[0].$')
      title = jpath.on(oaire)
      title = Sanitize.fragment(title)

      authors = []
      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].creator[*]')
      results = jpath.on(oaire)
      results.each_with_index do |author, _index|
        aut = CBGP::Publication::Author.new(name: author['$'], orcid: author['@orcid'], rank: "0")
        aut = Sanitize.fragment(aut)
        # rank is totally useless from open aire
        authors << aut
      end

      date = ''      #      response.results.result[0].metadata["oaf:entity"]["oaf:result"].children.result[1].dateofacceptance
      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].children.result[*]')
      results = jpath.on(oaire)
      results.each_with_index do |entity, _index|
        next unless entity['dateofacceptance'] 
        date = entity['dateofacceptance']['$']
        date = date[0..9] # cut off the zenith time
        warn "OADATE", date, "\n\n"
      end

      doi = ''
      #                     response.results.result[0].metadata["oaf:entity"]["oaf:result"].originalId[1].$
      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].originalId')
      results = jpath.on(oaire)
      results.each_with_index do |entity, _index|
        next unless entity['$'].match(/^10\.\d{4,}(?:\.\d+)*\/[A-Za-z0-9]+(?:[-._\/:][A-Za-z0-9]+)*$/) # DOi regexp
        doi = entity['$']
      end

      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].journal["@vol"]')
      volume = jpath.on(oaire)

      # OpenAPIRE graph doesn't capture this!
      # issue = ''
      # path = JsonPath.new('')
      # issue = jpath.on(oaire)

      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].journal["@sp"]')
      startpage = jpath.on(oaire)

      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].journal["@ep"]')
      endpage = jpath.on(oaire)
      pub = CBGP::Publication.new(
        doi: doi,
        authors: [authors], # make it a list of lists so that only one instance is sent to the widget
        affiliations: [affiliations],
        title: title,
        journal: journal,
        date: date,
        cbgp_corresponding: '',
        pubtype: '',
        oa: '',
        scopusq: '',
        scopusd1: '',
        sochoa: ''
      )

      # warn "PUB = #{pub.inspect}"
      pub
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

      affiliations = []
      # Define the JSONPath query with a wildcard to match all "rel" elements
      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].rels.rel[*].legalname.$') # the affiliation name
      # Execute the query and get all matches
      results = jpath.on(oaire)
      # Loop through the results and print each legalname
      results.each_with_index do |legalname, index|
        puts "rel[#{index}].legalname: #{legalname}"
        affiliations << legalname
      end
      pub.affiliations = [affiliations]

      oa = ""
      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].bestaccessright["@classid"]')
      result = jpath.on(oaire)
      pub.oa = "Yes" if result.first == "OPEN"
        

      pub
    end
  end
end
