module CBGP
  class Parsers
    # Matches raw author records (as produced by datacite_parser,
    # crossref_parser, openaire_parser) against existing CBGP `member`
    # records, to find which authors of a loaded publication are CBGP
    # personnel.
    #
    # Matching is intentionally exact-or-nothing, never fuzzy: an ORCID match
    # is unambiguous; a name match requires the full given+family name to
    # agree once accents are stripped. A false positive here would wrongly
    # attribute an outside co-author's identity to a CBGP member, which is
    # worse than under-matching (missed matches can be fixed by hand later).
    #
    # Journal/DOI-registry metadata frequently drops diacritics that the
    # canonical personnel record keeps (e.g. a paper's "Garcia" vs. the
    # authoritative "García" in the member file), so both sides are unaccented
    # before comparison - the member record's spelling is never assumed to be
    # the one that's wrong.
    #
    # @param authors [Array<Hash>] each with :name, :given, :family, :orcid
    # @return [Array<String>] ORCIDs of matched CBGP personnel, deduplicated
    def self.match_authors_to_personnel(authors:)
      return [] if authors.to_a.empty?

      members = load_member_index

      matched = authors.filter_map do |author|
        member = find_member_by_orcid(members, author[:orcid]) ||
                 find_member_by_name(members, author[:given], author[:family])
        member && !member[:orcid].to_s.strip.empty? ? member[:orcid] : nil
      end

      matched.uniq
    end

    def self.find_member_by_orcid(members, orcid)
      orcid = orcid.to_s.strip
      return nil if orcid.empty?

      members.find { |m| m[:orcid].to_s.strip == orcid }
    end
    private_class_method :find_member_by_orcid

    def self.find_member_by_name(members, given, family)
      given = unaccent(given.to_s).strip.downcase
      family = unaccent(family.to_s).strip.downcase
      return nil if given.empty? || family.empty?

      members.find do |m|
        unaccent(m[:name].to_s).strip.downcase == given &&
          unaccent(m[:surname].to_s).strip.downcase == family
      end
    end
    private_class_method :find_member_by_name

    # Loads every member's name/surname/orcid once, so matching a
    # publication's whole author list costs one broad search instead of one
    # query per author.
    def self.load_member_index
      graphs = execute_search(dataset_type: 'member', broad: true) || []
      graphs.filter_map do |graph|
        member = CBGP::Dataset.load_from_graph(graph: graph, database: 'member')
        next unless member

        { name: member.name, surname: member.surname, orcid: member.orcid }
      rescue StandardError => e
        warn "Skipping unreadable member graph #{graph}: #{e.inspect}"
        nil
      end
    end
  end
end
