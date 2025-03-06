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
      return false if journal.empty?

      affiliations = []
      # Define the JSONPath query with a wildcard to match all "rel" elements
      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].rels.rel[*].legalname.$') # the affiliation name
      # jpath = JsonPath.new('$["response"]["results"]["result"][0]["metadata"]["oaf:entity"]["oaf:result"]["rels"]["rel"][*]["legalname"]')
      # Execute the query and get all matches
      results = jpath.on(oaire)
      # Loop through the results and print each legalname
      results.each_with_index do |legalname, index|
        puts "rel[#{index}].legalname: #{legalname}"
        affiliations << legalname
      end

      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].title[0].$')
      title = jpath.on(oaire)

      authors = []
      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].creator[*]')
      results = jpath.on(oaire)
      results.each_with_index do |author, _index|
        aut = CBGP::Publication::Author.new(name: author['$'], orcid: author['@orcid'], rank: author['@rank'])
        authors << aut
      end

      date = ''      #      response.results.result[0].metadata["oaf:entity"]["oaf:result"].children.result[1].dateofacceptance
      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].children.result[*]')
      results = jpath.on(oaire)

      results.each_with_index do |entity, _index|

        next unless entity['dateofacceptance'] 

        date = entity['dateofacceptance']['$']
      end

      doi = ''
      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].pid[*]')
      results = jpath.on(oaire)
      results.each_with_index do |entity, _index|
        next unless entity['@classid'] == 'doi'

        doi = entity['$']
        warn "doi #{doi}"
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

      full_ref = "#{journal} #{volume} (#{date}) pp#{startpage}-#{endpage}"

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

      warn "PUB = #{pub.inspect}"
      pub
    end
  end
end
