module CBGP
  class Parsers
    # Crossref's controlled type vocabulary (https://api.crossref.org/types,
    # e.g. "journal-article", "book-chapter", "posted-content") and
    # DataCite's CSL-JSON "type" field (from the citeproc content
    # negotiation datacite_parser.rb uses, e.g. "article-journal", "chapter",
    # "book-chapter") are both hyphenated and loosely overlapping, but
    # neither maps cleanly onto this ontology's cbgp:publication-type field,
    # which currently only distinguishes two answers: "Article" and "Book"
    # (no separate "Book Chapter" - see docs/source or flag to the ontology
    # maintainer if finer granularity is ever wanted). Classification here is
    # therefore a coarse, keyword-based bucket, not a full bibliographic
    # taxonomy - a book chapter lands in "Book", same as a monograph.
    #
    # Defaults to "Article" whenever the source type is missing or doesn't
    # match a known "book" keyword, since that covers the vast majority of
    # real CBGP publications (per the user, 2026-08-26).
    BOOK_TYPE_KEYWORDS = %w[book monograph chapter].freeze

    def self.classify_publication_type(type_string)
      normalized = type_string.to_s.downcase
      return 'Article' if normalized.empty?

      BOOK_TYPE_KEYWORDS.any? { |kw| normalized.include?(kw) } ? 'Book' : 'Article'
    end

    # Resolves a publication_type answer label ("Article"/"Book") to the
    # ontology's stored answerid fragment (e.g. "ptype1") - looked up
    # dynamically against the live answer block rather than hardcoded, so a
    # future ontology edit that renumbers or relabels these answers can't
    # silently break this (see feedback_design_for_ontology_churn).
    #
    # @return [String, nil] the answerid fragment, or nil if no answer with
    #   that label currently exists (degrades to leaving the field unset,
    #   same as before this feature existed)
    def self.publication_type_answer_id(label)
      match = get_answer_block_query(ablockid: 'publication-type', language: 'en')
              .find { |a| a[:label].to_s.strip.casecmp?(label.to_s.strip) }
      match && match[:aid].to_s.gsub(/.*#/, '')
    end
  end
end
