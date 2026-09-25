module CBGP
  class Parsers
    OPEN_LICENSE_PATTERNS = [
      %r{creativecommons\.org}i,
      /creative\s*commons/i,
      /\bcc0\b/i,
      /\bcc-by\b/i,
      /public\s*domain/i,
      %r{opendefinition\.org}i
    ].freeze

    # Both classifiers below deliberately only ever return "Yes" or nil
    # (leave unset) - never "No". Absence of a recognized open-license
    # signal doesn't prove a paper is closed (it could be open via a route
    # neither registry tracks, e.g. green OA self-archiving), so only a
    # confident positive is worth recording. Per the user (2026-08-26),
    # OpenAIRE must never be used for this at all - its bestaccessright
    # field previously overwrote whatever Crossref/DataCite had determined,
    # on every single publication (see openaire_parser.rb's
    # #openaire_affiliations, which no longer touches pub.oa).

    # Crossref's own "license" field: an array of
    # {URL, content-version, delay-in-days, ...} entries. "Yes" only when at
    # least one entry points to a recognized open license AND has no
    # embargo (delay-in-days == 0).
    def self.classify_open_access_from_crossref(license_entries)
      open = Array(license_entries).any? do |entry|
        url = entry['URL'].to_s
        delay = entry['delay-in-days'].to_i
        delay.zero? && OPEN_LICENSE_PATTERNS.any? { |pat| url.match?(pat) }
      end
      open ? 'Yes' : nil
    end

    # DataCite-registered DOIs, fetched via doi.org's citeproc content
    # negotiation (same request datacite_parser.rb already makes - no extra
    # API call needed), carry a free-text "copyright" string (e.g.
    # "Creative Commons Attribution 4.0 International") rather than
    # Crossref's structured license array.
    def self.classify_open_access_from_datacite(copyright_text)
      OPEN_LICENSE_PATTERNS.any? { |pat| copyright_text.to_s.match?(pat) } ? 'Yes' : nil
    end

    # Resolves an open_access answer label ("Yes"/"No") to the ontology's
    # stored answerid fragment (e.g. "oa_yes") - looked up dynamically
    # against the live answer block rather than hardcoded, same pattern as
    # publication_type_answer_id (see lib/publication_type_classifier.rb).
    def self.open_access_answer_id(label)
      return nil if label.to_s.strip.empty?

      match = get_answer_block_query(ablockid: 'open_access', language: 'en')
              .find { |a| a[:label].to_s.strip.casecmp?(label.to_s.strip) }
      match && match[:aid].to_s.gsub(/.*#/, '')
    end
  end
end
