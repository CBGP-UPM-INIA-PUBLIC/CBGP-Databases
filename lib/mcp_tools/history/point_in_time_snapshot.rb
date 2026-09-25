# frozen_string_literal: true

require 'json'

module McpTools
  module History
    # MCP tool: "time travel" - the full reconstructed state of every
    # record of a form_type exactly as it stood on a specific past date,
    # not just what changed. Good for retrospective/compliance questions
    # ("what did our active projects look like on 2023-12-31") or matching
    # a past report's numbers exactly.
    class PointInTimeSnapshot
      NAME = 'point_in_time_snapshot'

      DESCRIPTION = <<~DESCRIPTION
        The full state of every record of a form_type as it stood on a
        specific past date - not a diff, the complete reconstructed record
        as it actually looked then. A record that didn't exist yet as of
        that date is simply absent from the result, not an error; a record
        deleted after that date but still existing then is included with
        its state at that time.

        Use this instead of search_records/aggregate (core server, which
        only ever see TODAY's state) whenever the question is anchored to a
        past date - "as of", "at the end of last year", matching a
        historical report.
      DESCRIPTION

      INPUT_SCHEMA = {
        type: 'object',
        properties: {
          form_type: { type: 'string' },
          as_of_date: { type: 'string', description: 'YYYY-MM-DD' }
        },
        required: %w[form_type as_of_date]
      }.freeze

      def self.call(arguments)
        snapshots = snapshot_as_of(form_type: arguments['form_type'], as_of_date: arguments['as_of_date'])

        records = snapshots.map do |s|
          s[:fields].merge('@id' => s[:graph_uri], 'primary_id' => s[:primary_id], 'as_of_generated_at' => s[:generated_at])
        end

        [{ type: 'text', text: { as_of_date: arguments['as_of_date'], total_records: records.size, records: records }.to_json }]
      end
    end
  end
end
