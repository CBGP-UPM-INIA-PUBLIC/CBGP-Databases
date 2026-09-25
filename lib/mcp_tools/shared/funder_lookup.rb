# frozen_string_literal: true

require 'json'
require 'rest-client'
require 'uri'

module McpTools
  module Shared
    # MCP tool: normalizes a free-text funder name (e.g. from
    # project_funding_institution, which is genuinely unpredictable - a
    # disease-specific charity can fund a one-off competition with no
    # warning and no guarantee it's registered anywhere) against the
    # Research Organization Registry (ror.org). ROR is a registry of
    # research ORGANIZATIONS generally, not a dedicated funder database -
    # it covers many real funders (it absorbed Crossref's old Funder
    # Registry data, hence the "funder" type some candidates carry), but a
    # name match by itself doesn't mean the matched organization actually
    # acts as a funder.
    #
    # Deliberately a thin passthrough, not a normalization pipeline: returns
    # ROR's own ranked candidates (with its own score/chosen signal) as-is
    # and leaves the actual judgment call - "is any of these genuinely the
    # organization the record means" - to the calling agent, not to a
    # confidence threshold hardcoded here. A funder simply not existing in
    # the registry is a normal, expected outcome, not a tool failure.
    #
    # No database access - never queries CBGP-Databases itself. Shared by
    # both MCP servers (registered identically on /mcp/core and
    # /mcp/history) since funder normalization is equally relevant to a
    # current-state search and a funding-trend-over-time question.
    class FunderLookup
      NAME = 'funder_lookup'
      ROR_ENDPOINT = 'https://api.ror.org/organizations'

      DESCRIPTION = <<~DESCRIPTION
        Looks up a funder/institution NAME (as it appears in a free-text
        field like project_funding_institution - not a controlled
        vocabulary, so spelling/abbreviation varies) against the Research
        Organization Registry (ror.org).

        IMPORTANT: ROR is a registry of research ORGANIZATIONS generally
        (universities, hospitals, institutes, government agencies,
        nonprofits) - it is NOT a dedicated funder database. It does cover
        many real funders (it absorbed Crossref's old Funder Registry
        data), and each candidate's "types" array tells you whether ROR
        itself tags that organization as a "funder" - treat that as a real
        positive signal. But a name match to a university or hospital is
        NOT evidence it's the funder in question, even at a high score;
        and a small, newly-founded, or single-purpose funding body (e.g. a
        disease-specific charity funding a one-off competition) legitimately
        may not be in ROR at all.

        Returns ROR's own ranked candidates, each with a score (0-1, ROR's
        own text-similarity signal), "ror_chosen" (ROR's own best-guess
        flag), and "types" - use this ONLY as a starting point. YOU must
        judge whether any candidate is genuinely the organization named in
        the record; a high score does not guarantee a real match. If
        nothing fits, tell the user this funder isn't in the registry
        rather than picking the least-bad candidate - that is a normal,
        common, and completely valid answer, not a tool failure. Never
        treat this as a reason to change or "correct" what's actually
        stored in the database - it's read-only enrichment for an answer,
        nothing more.
      DESCRIPTION

      INPUT_SCHEMA = {
        type: 'object',
        properties: {
          name: { type: 'string', description: 'The funder/institution name or abbreviation to look up' }
        },
        required: ['name']
      }.freeze

      def self.call(arguments)
        name = arguments['name'].to_s.strip
        raise ArgumentError, 'name is required' if name.empty?

        items = fetch_candidates(name)
        candidates = items.map { |item| extract_candidate(item) }

        [{ type: 'text', text: { query: name, candidates: candidates }.to_json }]
      end

      def self.fetch_candidates(name)
        url = "#{ROR_ENDPOINT}?#{URI.encode_www_form(affiliation: name)}"
        response = RestClient::Request.execute(method: :get, url: url, timeout: 10, open_timeout: 5)
        JSON.parse(response.body)['items'] || []
      rescue RestClient::Exception, SocketError, Errno::ECONNREFUSED, JSON::ParserError => e
        raise "ROR lookup failed for #{name.inspect}: #{e.class} #{e.message}"
      end
      private_class_method :fetch_candidates

      def self.extract_candidate(item)
        org = item['organization'] || {}
        names = org['names'] || []
        {
          ror_id: org['id'],
          name: names.find { |n| Array(n['types']).include?('ror_display') }&.dig('value'),
          acronym: names.find { |n| Array(n['types']).include?('acronym') }&.dig('value'),
          types: org['types'], # e.g. ["funder", "government"] - "funder" present is a real positive signal, absent is not a strong negative one
          country: org.dig('locations', 0, 'geonames_details', 'country_name'),
          score: item['score'],
          ror_chosen: item['chosen']
        }
      end
      private_class_method :extract_candidate
    end
  end
end
