module CBGP
  class Parsers
    # Matches raw author records (as produced by datacite_parser,
    # crossref_parser, openaire_parser) against existing CBGP `member`
    # records, to find which authors of a loaded publication are CBGP
    # personnel.
    #
    # Matching is exact-token, not fuzzy string similarity: an ORCID match is
    # unambiguous; a name match requires the given name's first token to
    # agree exactly and at least one surname token to agree exactly, once
    # accents are stripped. This is deliberately looser than a full-string
    # match (see git history around 2026-08-26 for why: a live stress test
    # against 272 real CBGP personnel records found the old full-string-match
    # rule missed 239/272 - 88% - once a name was truncated the way
    # Crossref/DataCite/OpenAIRE routinely truncate them, because most CBGP
    # staff carry Spanish double surnames or compound given names).
    #
    # The looser rule is safe specifically *because* of how this matcher is
    # used: match_authors_to_personnel is only ever run against the author
    # list of a publication that is already known to include at least one
    # CBGP author (the personnel-loading admin never runs this against an
    # arbitrary/random name), so the risk being guarded against is under-
    # matching a real CBGP co-author, not a coincidental token collision
    # against a stranger. A collision (matching to the wrong CBGP member
    # among several who share a surname) is a real, non-zero residual risk
    # under this rule, accepted deliberately as the tradeoff.
    #
    # Journal/DOI-registry metadata frequently drops diacritics that the
    # canonical personnel record keeps (e.g. a paper's "Garcia" vs. the
    # authoritative "García" in the member file), so both sides are unaccented
    # before comparison - the member record's spelling is never assumed to be
    # the one that's wrong.
    #
    # @param authors [Array<Hash>] each with :name, :given, :family, :orcid
    # @param member_index [Array<Hash>, nil] a pre-loaded #load_member_index
    #   result, to reuse across many publications in one bulk load instead of
    #   re-querying all of CBGP personnel for every single publication
    # @return [Array<String>] ORCIDs of matched CBGP personnel, deduplicated
    def self.match_authors_to_personnel(authors:, member_index: nil)
      return [] if authors.to_a.empty?

      members = member_index || load_member_index

      matched = authors.filter_map do |author|
        member = find_member_by_orcid(members, author[:orcid]) ||
                 find_member_by_name(members, author[:given], author[:family])
        member && !member[:orcid].to_s.strip.empty? ? member[:orcid] : nil
      end

      matched.uniq
    end

    def self.find_member_by_orcid(members, orcid)
      # ORCID's check digit can be 'X' (uppercase, its canonical form) but at
      # least one source (OpenAIRE) returns it lowercase - upcase both sides
      # so a source-specific casing quirk can't silently break an otherwise
      # exact, unambiguous match (found 2026-08-26).
      orcid = orcid.to_s.strip.upcase
      return nil if orcid.empty?

      members.find { |m| m[:orcid].to_s.strip.upcase == orcid }
    end
    private_class_method :find_member_by_orcid

    def self.find_member_by_name(members, given, family)
      given_first = unaccent(given.to_s).strip.downcase.split(/\s+/).first.to_s
      family_tokens = unaccent(family.to_s).strip.downcase.split(/\s+/)
      return nil if given_first.empty? || family_tokens.empty?

      members.find do |m|
        m_given_first = unaccent(m[:name].to_s).strip.downcase.split(/\s+/).first.to_s
        m_family_tokens = unaccent(m[:surname].to_s).strip.downcase.split(/\s+/)

        m_given_first == given_first && (family_tokens & m_family_tokens).any?
      end
    end
    private_class_method :find_member_by_name

    # Loads every member's name/surname/orcid in two queries total (one
    # broad search for the graphs, one batched fetch_datasets_raw_data call
    # for all of them) rather than one CBGP::Dataset.load_from_graph call per
    # member - that would be 2 extra SPARQL round-trips per member (~544 for
    # 272 real CBGP staff), which matters a lot here because
    # match_authors_to_personnel calls this on every single publication.
    def self.load_member_index
      graphs = execute_search(dataset_type: 'member', broad: true) || []
      return [] if graphs.empty?

      raw = fetch_datasets_raw_data(graph_uris: graphs, database: 'member')
      raw.map do |details|
        { name: details[:member_name], surname: details[:member_surnames], orcid: details[:member_orcid] }
      end
    end
  end
end
