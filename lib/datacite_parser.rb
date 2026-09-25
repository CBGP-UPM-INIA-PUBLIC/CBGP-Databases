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

      jpath = JsonPath.new('title')
      title = jpath.on(dcite).first
      return { pub: false, authors: [] } if title.to_s.strip.empty?

      title = Sanitize.fragment(title)

      # DataCite covers datasets, software, and other non-journal deposits
      # (e.g. Zenodo records) which legitimately have no "container-title" -
      # gating validity on journal presence silently discarded every real
      # non-journal DataCite DOI, found 2026-08-26 loading a real Zenodo DOI
      # whose DataCite record was otherwise complete. See crossref_parser.rb
      # for the same fix on the Crossref side.
      jpath = JsonPath.new('["container-title"]')
      journal = jpath.on(dcite).first
      journal = journal.first if journal.is_a?(Array)
      journal = Sanitize.fragment(journal.to_s)

      # not provided by datacite
      affiliations = []

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

      # The citeproc/CSL-JSON format this parser requests via Accept above
      # carries its own "type" field (e.g. "article-journal", "chapter",
      # "book-chapter", "software") - drives publication_type, which was
      # otherwise left unset on every import (found 2026-08-26). See
      # lib/publication_type_classifier.rb.
      jpath = JsonPath.new('type')
      raw_type = jpath.on(dcite).first

      # DataCite's citeproc "copyright" field (free text, e.g. "Creative
      # Commons Attribution 4.0 International") - drives publication_open_access.
      # See lib/open_access_classifier.rb: only ever sets "Yes", never "No",
      # never OpenAIRE.
      jpath = JsonPath.new('copyright')
      copyright_text = jpath.on(dcite).first

      dataset = CBGP::Dataset.new(type: 'publication')

      dataset.doi = doi
      dataset.authors = names_only # make it a list of lists so that only one instance is sent to the widget
      dataset.affiliations = affiliations
      dataset.title = title
      dataset.journal = journal
      dataset.date = date
      dataset.pubtype = publication_type_answer_id(classify_publication_type(raw_type))
      dataset.oa = open_access_answer_id(classify_open_access_from_datacite(copyright_text))

      { pub: dataset, authors: raw_authors }
    end
  end
end
