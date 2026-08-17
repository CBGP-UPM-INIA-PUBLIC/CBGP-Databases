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

      jpath = JsonPath.new('$["container-title"][0]')
      journal = jpath.on(message).first
      return { pub: false, authors: [] } if journal.to_s.strip.empty?

      jpath = JsonPath.new('$.title[0]')
      title = jpath.on(message).first
      title = Sanitize.fragment(title.to_s)

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

      { pub: dataset, authors: raw_authors }
    end
  end
end
