# frozen_string_literal: true

require 'json'

module McpTools
  module Core
    # MCP tool: the core database's search/filter interface. Same query
    # logic as the existing POST /cbgp/query-dataset/:database route
    # (execute_search -> fetch_datasets_raw_data), returned as compact
    # JSON-LD instead of rendering an HTML results page.
    class SearchRecords
      NAME = 'search_records'
      DEFAULT_LIMIT = 200

      DESCRIPTION = <<~DESCRIPTION
        Searches the core database for records of one form_type matching
        given field values. Call list_form_facets first to learn the exact
        questionclass identifiers and, for controlled-vocabulary fields,
        the exact id values this tool requires - free-text guesses at
        either will simply match nothing.

        search_params is an object of questionclass => value. A plain
        string value does an accent-insensitive partial-text match (e.g.
        "maria" matches "María"); for a controlled-vocabulary field, pass
        the exact id from list_form_facets, not the label. For a date
        field, pass {"start": "YYYY-MM-DD", "end": "YYYY-MM-DD"} - either
        bound may be omitted for an open-ended range. Omit search_params
        (or pass {}) to list every record of that form_type.

        Returns each matching record as compact JSON-LD: an @id (the
        record's stable graph URI - pass this directly as the value/
        primary_id argument to the History-server tools to see that
        record's edit history) plus every field that has a value. Results
        are capped (see "limit"); total_matches tells you whether anything
        was left out.
      DESCRIPTION

      INPUT_SCHEMA = {
        type: 'object',
        properties: {
          form_type: { type: 'string', description: 'e.g. "member", "project", "publication"' },
          search_params: {
            type: 'object',
            description: 'questionclass => value (string) or {start, end} (date range). Omit for all records.'
          },
          limit: { type: 'integer', description: "Max records to return (default #{DEFAULT_LIMIT})" }
        },
        required: ['form_type']
      }.freeze

      def self.call(arguments)
        form_type = arguments['form_type']
        search_params = arguments['search_params'] || {}
        limit = (arguments['limit'] || DEFAULT_LIMIT).to_i

        all_graph_uris = execute_search(dataset_type: form_type, search_params: search_params)
        graph_uris = all_graph_uris.first(limit)

        raw_records = fetch_datasets_raw_data(graph_uris: graph_uris, database: form_type)
        records = JsonldCompact.serialize_records(form_type: form_type, raw_records: raw_records)

        [{ type: 'text', text: { total_matches: all_graph_uris.size, returned: records.size, records: records }.to_json }]
      end
    end
  end
end
