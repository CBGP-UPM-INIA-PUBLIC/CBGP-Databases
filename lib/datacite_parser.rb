require 'json'
module CBGP
  class Parsers
    def self.datacite_parser(doi:)
      headers = {
        'Accept' => 'application/vnd.citationstyles.csl+json'
      }
      dcite = nil
      retry_attempts = 0
      begin
        warn "https://doi.org/#{doi}"
        json = RestClient.get("https://doi.org/#{doi}", headers)
        dcite = JSON.parse(json)
      rescue StandardError => e
        warn "error #{e.inspect}"
        retry_attempts += 1
        if retry_attempts < 5
          retry
        else
          warn 'failed.  next'
          return false
        end
      end

      jpath = JsonPath.new('["container-title"]')
      journal = jpath.on(dcite).first
      return false unless journal
      return false if journal.empty?

      # not provided by datacite
      affiliations = []

      jpath = JsonPath.new('title')
      title = jpath.on(dcite).first
      title = Sanitize.fragment(title)

      authors = []
      jpath = JsonPath.new('author[*]')
      results = jpath.on(dcite)
      results.each_with_index do |author, index|
        aname = 'Authorship not found in record'
        orcid = ''
        if author.respond_to? '[]'
          orcid = author['ORCID'].gsub(%r{https?://orcid.org/}, '') if author['ORCID']
          orcid = Sanitize.fragment(orcid)
          aname = "#{author['given']} #{author['family']}"
          aname = Sanitize.fragment(aname)
        end

        # aut = CBGP::Publication::Author.new(name: aname, orcid: orcid,
        #                                     rank: "#{index.to_i + 1}") # start rank at 1 not 0
        authors << aname
      end

      jpath = JsonPath.new('created["date-time"]')
      results = jpath.on(dcite).first
      date = '1900-01-01'
      date = results[0..9] if results # comes back as dateand time - TODO can also be "issued", which is more complex
      # warn "DCDATE", date, "\n\n"

      jpath = JsonPath.new('DOI')
      doi = jpath.on(dcite).first
      doi = Sanitize.fragment(doi)

      ####  HERE!!

      jpath = JsonPath.new('volume')
      volume = jpath.on(dcite).first

      # OpenAPIRE graph doesn't capture this!
      # issue = ''
      # path = JsonPath.new('')
      # issue = jpath.on(oaire)

      jpath = JsonPath.new('page')
      pages = jpath.on(dcite).first
      startpage = pages
      endpage = pages
      # jpath.on(dcite).split('-')

      dataset = CBGP::Dataset.new(type: 'publication')

      dataset.doi = doi
      dataset.authors = authors # make it a list of lists so that only one instance is sent to the widget
      dataset.affiliations = [affiliations]
      dataset.title = title
      dataset.journal = journal
      dataset.date = date

      # abort "affiliations #{affiliations.inspect} pub: #{pub.affiliations}"
      # warn "PUB = #{pub.inspect}"

      dataset
    end
  end
end
