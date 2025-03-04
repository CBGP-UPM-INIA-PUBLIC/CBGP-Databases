require_relative 'queries'
require_relative 'core'

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
    attr_accessor :doi, :authors, :affiliations, :title, :year, :date, :uniqid, :cbgp_corresponding
    attr_accessor :type, :oa, :scopusq, :scopusd1, :sochoa

    def initialize(doi: '', authors: [], affiliations: [], 
                  title: '', year: '', date: '', 
                  cbgp_corresponding: "false", type: "", 
                  oa: "false", scopusq: "", scopusd1: "", sochoa: "false", uniqid: '')

      @doi = doi
      @authors = authors
      @affiliations = affiliations
      @title = title
      @year = year
      @date = date
      @cbgp_corresponding = cbgp_corresponding
      @type = type
      @oa = oa
      @scopusq = scopusq
      @scopusd1 = scopusd1
      @sochoa = sochoa
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
