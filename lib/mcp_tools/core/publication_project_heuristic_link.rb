# frozen_string_literal: true

require 'date'
require 'json'

module McpTools
  module Core
    # MCP tool: there is no field anywhere in the ontology linking a
    # publication to the project(s) that funded it (confirmed by
    # enumerating every project_*/publication_* questionclass), so a
    # question like "which publications came out of this project" cannot
    # be answered by a clean join. This is the agreed-upon fallback: match
    # publications whose author-ORCID field overlaps the project's PI/co-PI
    # ORCIDs, restricted to publication dates inside the project's date
    # range (plus a grace period, since publication lags funding). Every
    # result is explicitly marked inferred, not authoritative - see the
    # MCP servers plan for why a real cross-reference field wouldn't even
    # fix old records retroactively.
    #
    # Deliberately takes the relevant field names as arguments rather than
    # hardcoding them: project_pi_orcid vs personnel_project_responsible_pi_orcid
    # are different questionclasses on the two project form_types, so there
    # is no single hardcoded name that would be correct for both. Call
    # list_form_facets on both form_types first to find the right ones.
    class PublicationProjectHeuristicLink
      NAME = 'publication_project_heuristic_link'

      DESCRIPTION = <<~DESCRIPTION
        Approximates which publications a project produced - THERE IS NO
        REAL LINK IN THE DATABASE for this, so every result here is
        inferred, not authoritative. Matches a publication to the project
        when an ORCID in the publication's author field also appears in one
        of the project's PI/co-PI fields, and the publication's date falls
        within the project's date range (extended by grace_period_days, to
        allow for publication lag after a project ends).

        Always tell the user these matches are inferred from shared
        authorship and date overlap, not a stored relationship - do not
        present them as certain.

        Call list_form_facets on both form_types first: pi_orcid_fields and
        publication_author_orcid_field must be exact questionclass names
        (they differ between the "project" and "personnel_project" forms -
        e.g. project_pi_orcid vs personnel_project_responsible_pi_orcid).
      DESCRIPTION

      INPUT_SCHEMA = {
        type: 'object',
        properties: {
          project_form_type: { type: 'string', description: 'e.g. "project" or "personnel_project"' },
          project_primary_id: { type: 'string' },
          pi_orcid_fields: {
            type: 'array', items: { type: 'string' },
            description: 'questionclass(es) on the project form holding ORCID values, e.g. ["project_pi_orcid", "project_co_pi"]'
          },
          project_start_date_field: { type: 'string' },
          project_end_date_field: { type: 'string' },
          publication_form_type: { type: 'string', description: 'default "publication"' },
          publication_date_field: { type: 'string', description: 'default "publication_date"' },
          publication_author_orcid_field: { type: 'string', description: 'questionclass on the publication form holding author ORCIDs' },
          grace_period_days: { type: 'integer', description: 'default 365' }
        },
        required: %w[project_form_type project_primary_id pi_orcid_fields project_start_date_field
                      project_end_date_field publication_author_orcid_field]
      }.freeze

      def self.call(arguments)
        project = fetch_project(arguments)
        pi_orcids = arguments['pi_orcid_fields'].flat_map { |f| Array(project[f.to_sym]) }.compact.to_set

        window = date_window(project, arguments)
        candidates = fetch_candidate_publications(arguments, window)

        matches = candidates.filter_map { |pub| match_entry(pub, pi_orcids, arguments) }

        [{ type: 'text', text: { note: 'INFERRED from shared ORCID + date overlap, not a stored relationship', matches: matches }.to_json }]
      end

      def self.fetch_project(arguments)
        graph_row = retrieve_dataset_graph_query(primary_id: arguments['project_primary_id']).first
        unless graph_row
          raise "No #{arguments['project_form_type']} record found with primary_id #{arguments['project_primary_id'].inspect}"
        end

        fetch_datasets_raw_data(graph_uris: [graph_row[:g].to_s], database: arguments['project_form_type']).first
      end
      private_class_method :fetch_project

      def self.date_window(project, arguments)
        start_date = Array(project[arguments['project_start_date_field'].to_sym]).first
        end_date = Array(project[arguments['project_end_date_field'].to_sym]).first
        grace_days = (arguments['grace_period_days'] || 365).to_i

        window_end = end_date ? (Date.parse(end_date) + grace_days).iso8601 : nil
        { start: start_date, end: window_end }
      end
      private_class_method :date_window

      def self.fetch_candidate_publications(arguments, window)
        publication_form_type = arguments['publication_form_type'] || 'publication'
        publication_date_field = arguments['publication_date_field'] || 'publication_date'

        search_params = window[:start] || window[:end] ? { publication_date_field => window } : {}
        graph_uris = execute_search(dataset_type: publication_form_type, search_params: search_params)
        fetch_datasets_raw_data(graph_uris: graph_uris, database: publication_form_type)
      end
      private_class_method :fetch_candidate_publications

      def self.match_entry(publication, pi_orcids, arguments)
        author_orcids = Array(publication[arguments['publication_author_orcid_field'].to_sym])
        matched = author_orcids & pi_orcids.to_a
        return nil if matched.empty?

        {
          publication: publication[:dataset],
          matched_orcid: matched.first
        }
      end
      private_class_method :match_entry
    end
  end
end
