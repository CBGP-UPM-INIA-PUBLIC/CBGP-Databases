# frozen_string_literal: true

require 'json'

module McpTools
  module History
    # MCP tool: finds every record of a form_type matching given field
    # values/date ranges, evaluated against each record's LATEST KNOWN
    # state (current if it still exists, otherwise its last state before
    # deletion) - durable against later deletes, unlike a plain current-
    # state search. Same search_params shape as the core server's
    # search_records, split into facets (exact match) and date_ranges.
    class TemporalSearch
      NAME = 'temporal_search'

      DESCRIPTION = <<~DESCRIPTION
        Finds every record of a form_type matching given field values
        and/or date ranges, evaluated against each record's latest known
        state - current if it still exists, otherwise its state just
        before deletion, so a record deleted after being queried doesn't
        vanish from a later re-run of the same question.

        facets is questionclass => exact value (e.g. {"project_type":
        "European"}). date_ranges is questionclass => {"start", "end"}
        (either bound may be omitted for an open range). Call
        list_form_facets (core server) first for exact questionclass names
        and controlled-vocabulary ids. Omit both to list every known
        record of that form_type.
      DESCRIPTION

      INPUT_SCHEMA = {
        type: 'object',
        properties: {
          form_type: { type: 'string' },
          facets: { type: 'object', description: 'questionclass => exact value' },
          date_ranges: { type: 'object', description: 'questionclass => {start, end}' }
        },
        required: ['form_type']
      }.freeze

      def self.call(arguments)
        snapshots = filter_snapshots_during(
          form_type: arguments['form_type'],
          facets: arguments['facets'] || {},
          date_ranges: normalized_date_ranges(arguments['date_ranges'])
        )

        records = snapshots.map do |snap|
          snapshot_fields(triples: snap[:triples]).merge('@id' => snap[:graph_uri], 'primary_id' => snap[:primary_id])
        end

        [{ type: 'text', text: { total_matches: records.size, records: records }.to_json }]
      end

      def self.normalized_date_ranges(date_ranges)
        (date_ranges || {}).transform_values { |r| { start: r['start'], end: r['end'] } }
      end
      private_class_method :normalized_date_ranges
    end
  end
end
