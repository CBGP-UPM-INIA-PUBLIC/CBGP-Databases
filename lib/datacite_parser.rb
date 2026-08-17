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
        if retry_attempts < 2
          retry
        else
          warn 'failed.  next'
          return { pub: false, authors: [] }
        end
      end

      jpath = JsonPath.new('["container-title"]')
      journal = jpath.on(dcite).first
      return { pub: false, authors: [] } unless journal
      return { pub: false, authors: [] } if journal.empty?

      # not provided by datacite
      affiliations = []

      jpath = JsonPath.new('title')
      title = jpath.on(dcite).first
      title = Sanitize.fragment(title)

      raw_authors = []
      names_only = []
      jpath = JsonPath.new('author[*]')
      results = jpath.on(dcite)
      results.each do |author|
        given = ''
        family = ''
        orcid = ''
        aname = 'Authorship not found in record'
        if author.respond_to? '[]'
          orcid = author['ORCID'].gsub(%r{https?://orcid.org/}, '') if author['ORCID']
          orcid = Sanitize.fragment(orcid)
          given = Sanitize.fragment(author['given'].to_s)
          family = Sanitize.fragment(author['family'].to_s)
          aname = "#{given} #{family}"
        end

        raw_authors << { name: aname, given: given, family: family, orcid: orcid }
        names_only << aname
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
      dataset.authors = names_only # make it a list of lists so that only one instance is sent to the widget
      dataset.affiliations = affiliations
      dataset.title = title
      dataset.journal = journal
      dataset.date = date

      { pub: dataset, authors: raw_authors }
    end
  end
end
