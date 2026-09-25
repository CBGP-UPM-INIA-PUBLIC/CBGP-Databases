require 'json'
module CBGP
  class Parsers
    # Parses publication metadata directly from the Crossref REST API
    # (api.crossref.org), for DOIs whose registration agency is Crossref.
    #
    # Mirrors datacite_parser.rb's contract: returns a Hash with the built
    # +:pub+ Dataset (or +false+ on failure) and the raw +:authors+ list (name
    # plus, when Crossref provides one, ORCID) so the caller can attempt
    # personnel cross-referencing without re-fetching.
    def self.crossref_parser(doi:)
      url = "https://api.crossref.org/works/#{doi}"
      cref = nil
      retry_attempts = 0
      begin
        warn url
        json = RestClient.get(url)
        cref = JSON.parse(json)
      rescue StandardError => e
        warn "crossref error #{e.inspect}"
        retry_attempts += 1
        retry if retry_attempts < 2
        return { pub: false, authors: [] }
      end

      message = cref['message']
      return { pub: false, authors: [] } unless message

      jpath = JsonPath.new('$.title[0]')
      title = jpath.on(message).first
      return { pub: false, authors: [] } if title.to_s.strip.empty?

      title = Sanitize.fragment(title.to_s)

      # "container-title" is the journal name - present for journal
      # articles, but legitimately absent for preprints (bioRxiv/medRxiv
      # "posted-content" records) and other non-journal work types. Treating
      # a missing journal as "not a valid publication" silently discarded
      # every real preprint DOI - found 2026-08-26 loading a real bioRxiv
      # DOI whose Crossref record was otherwise complete. Fall back to the
      # posting institution (e.g. "bioRxiv") or the publisher when there's
      # no journal, rather than rejecting the record outright.
      jpath = JsonPath.new('$["container-title"][0]')
      journal = jpath.on(message).first
      if journal.to_s.strip.empty?
        journal = message.dig('institution', 0, 'name') || message['publisher']
      end
      journal = Sanitize.fragment(journal.to_s)

      raw_authors = []
      names_only = []
      (message['author'] || []).each do |author|
        given = Sanitize.fragment(author['given'].to_s)
        family = Sanitize.fragment(author['family'].to_s)
        orcid = author['ORCID'].to_s.gsub(%r{https?://orcid.org/}, '')
        orcid = Sanitize.fragment(orcid)
        aname = "#{given} #{family}".strip
        aname = 'Authorship not found in record' if aname.empty?

        raw_authors << { name: aname, given: given, family: family, orcid: orcid }
        names_only << aname
      end

      date_parts = message.dig('published', 'date-parts', 0) ||
                   message.dig('created', 'date-parts', 0)
      date = if date_parts
               y, m, d = date_parts
               format('%04d-%02d-%02d', y.to_i, (m || 1).to_i, (d || 1).to_i)
             else
               '1900-01-01'
             end

      dataset = CBGP::Dataset.new(type: 'publication')
      dataset.doi = Sanitize.fragment(message['DOI'].to_s)
      dataset.authors = names_only
      dataset.affiliations = []
      dataset.title = title
      dataset.journal = journal
      dataset.date = date
      # See lib/publication_type_classifier.rb - Crossref's own "type" field
      # (e.g. "journal-article", "book-chapter") drives this, since it was
      # otherwise left unset on every import (found 2026-08-26, real example:
      # 10.1142/9789811265679_0033, a book chapter).
      dataset.pubtype = publication_type_answer_id(classify_publication_type(message['type']))
      # See lib/open_access_classifier.rb - only ever sets "Yes" from a
      # confident Crossref license signal, never "No", never OpenAIRE.
      dataset.oa = open_access_answer_id(classify_open_access_from_crossref(message['license']))

      { pub: dataset, authors: raw_authors }
    end
  end
end
