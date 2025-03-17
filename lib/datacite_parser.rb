module CBGP
  class Parsers
    def self.datacite_parser(doi:)
      headers = {
        'Accept' => 'application/vnd.citationstyles.csl+json'
      }
      dcite = nil
      begin
        warn "https://doi.org/#{doi}"
        json = RestClient.get("https://doi.org/#{doi}", headers)
        dcite = JSON.parse(json)
      rescue StandardError => e
        warn "error #{e.inspect}"
        return false
      end

      jpath = JsonPath.new('["container-title"]')
      journal = jpath.on(dcite).first
      return false if journal.empty?

      # not provided by datacite
      affiliations = []

      jpath = JsonPath.new('title')
      title = jpath.on(dcite).first

      authors = []
      jpath = JsonPath.new('author[*]')
      results = jpath.on(dcite)
      results.each_with_index do |author, index|
        orcid = author['ORCID'].gsub(/https?\:\/\/orcid.org\//, "") if author['ORCID']
        aut = CBGP::Publication::Author.new(name: "#{author['given']} #{author['family']}", orcid: orcid,
                                            rank: "#{index.to_i + 1}")  # start rank at 1 not 0
        authors << aut
      end
      jpath = JsonPath.new('created["date-time"]')
      results = jpath.on(dcite).first
      # warn "results #{results.inspect}"
      date = results[0..9] # comes back as dateand time
      warn "DCDATE", date, "\n\n"

      jpath = JsonPath.new('DOI')
      doi = jpath.on(dcite).first

      ####  HERE!!

      jpath = JsonPath.new('volume')
      volume = jpath.on(dcite).first

      # OpenAPIRE graph doesn't capture this!
      # issue = ''
      # path = JsonPath.new('')
      # issue = jpath.on(oaire)

      jpath = JsonPath.new('page')
      pages = jpath.on(dcite).first
      startpage= pages
      endpage = pages
      # jpath.on(dcite).split('-')

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
