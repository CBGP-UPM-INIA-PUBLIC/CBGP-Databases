require_relative 'queries'
require_relative 'core'

module CBGP
  class Publication
    attr_accessor :doi, :authors, :affiliations, :title, :year, :date, :uniqid

    def initialize(doi: '', authors: [], affiliations: [], title: '', year: '', date: '', uniqid: '')
      # GET THE LABELS HERE
      @doi = doi
      @authors = authors
      @affiliations = affiliations
      @title = title
      @year = year
      @date = date
      @uniqid = Time.now.to_i unless uniqid
    end

    def self.load_from_json(json:)
      begin
        oaire = JSON.parse(json)
      rescue StandardError
        return false
      end
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
      results.each_with_index do |author, index|
        puts "rel[#{index}].author: #{author}"
        authors << author
      end

      date = ''
      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].relevantdate[*]')
      results = jpath.on(oaire)
      results.each_with_index do |entity, _index|
        next unless entity['@classid'] == 'published-print'

        date = entity['$']
        warn "date #{date}"
      end

      doi = ''
      jpath = JsonPath.new('response.results.result[0].metadata["oaf:entity"]["oaf:result"].children.instance[3].pid[*]')
      results = jpath.on(oaire)
      results.each_with_index do |entity, _index|
        next unless entity['@classid'] == 'doi'

        doi = entity['$']
        warn "doi #{doi}"
      end

      pub = CBGP::Publication.new(
        doi: doi,
        authors: authors,
        affiliations: affiliations,
        title: title,
        year: date,
        date: date
      )

      warn "PUB = #{pub.inspect}"
      pub
    end

    def write_to_db
      warn inspect
      write_pub_to_db_query(pub: self)
    end
  end
end
