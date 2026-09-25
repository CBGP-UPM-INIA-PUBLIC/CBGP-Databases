# frozen_string_literal: true

require 'json'

module McpTools
  module History
    # MCP tool: the complete version history of one record, resolved by an
    # identifying field - the whole reason this History database exists.
    # Unlike the existing GET /cbgp/history/:database/:questionclass/:value
    # route (which dumps raw JSON-LD triples per version, designed as a
    # generic API response), this returns each version's flat field values
    # PLUS a field-level diff from the previous version - the actual answer
    # to "what changed and when", not raw data the caller has to diff
    # itself.
    class RecordHistory
      NAME = 'record_history'

      DESCRIPTION = <<~DESCRIPTION
        The complete version history of one record - every edit and delete,
        from creation to now, in chronological order. Each version includes
        its full field values AND a "changed" list showing exactly what was
        added/removed/changed from the immediately previous version (the
        first version's "changed" list is every field, since there's
        nothing before it to compare against).

        Resolve the record by an identifying field, e.g. form_type
        "member", questionclass "member_orcid", value "0000-0001-2345-6789"
        - call list_form_facets (core server) first for exact questionclass
        names. Raises a clear error if nothing matches that identifier,
        current or historical.

        For a chart-ready version of this same data, use record_timeline
        instead.
      DESCRIPTION

      INPUT_SCHEMA = {
        type: 'object',
        properties: {
          form_type: { type: 'string' },
          questionclass: { type: 'string', description: 'Identifying field, e.g. "member_orcid"' },
          value: { type: 'string', description: 'The identifying value' }
        },
        required: %w[form_type questionclass value]
      }.freeze

      def self.call(arguments)
        form_type = arguments['form_type']
        primary_id = resolve_primary_id(form_type, arguments)
        versions = full_timeline(form_type: form_type, primary_id: primary_id)

        timeline = build_timeline(versions)

        [{ type: 'text', text: { form_type: form_type, primary_id: primary_id, timeline: timeline }.to_json }]
      end

      def self.resolve_primary_id(form_type, arguments)
        primary_id = find_primary_id(form_type: form_type, questionclass: arguments['questionclass'], value: arguments['value'])
        return primary_id if primary_id

        raise "No #{form_type} record found with #{arguments['questionclass']} = #{arguments['value'].inspect}"
      end
      private_class_method :resolve_primary_id

      def self.build_timeline(versions)
        previous_fields = nil
        versions.map do |v|
          fields = snapshot_fields(triples: v[:triples])
          entry = {
            graph_uri: v[:graph_uri],
            generated_at: v[:generated_at],
            invalidated_at: v[:invalidated_at],
            reason: v[:reason],
            detail: v[:detail],
            fields: fields,
            changed: diff_snapshot_fields(before: previous_fields, after: fields)
          }
          previous_fields = fields
          entry
        end
      end
      private_class_method :build_timeline
    end
  end
end
