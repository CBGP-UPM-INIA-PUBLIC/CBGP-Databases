# frozen_string_literal: true

require 'json'

module McpTools
  module History
    # MCP tool: one record's version history, pre-shaped as
    # render_chart-ready timeline rows ({label, start, end}) - the same
    # underlying data as record_history, formatted for the visualization
    # instead of for narrative "what changed" answers.
    class RecordTimeline
      NAME = 'record_timeline'

      DESCRIPTION = <<~DESCRIPTION
        One record's version history shaped for render_chart's "timeline"
        chart_type directly - one row per version. Pass summary_field (a
        questionclass, e.g. "member_category") to label each span with that
        field's value during that period - e.g. a career timeline:
        "Predoctoral" 2018-2021, "Postdoctoral" 2021-2024, "Staff Scientist"
        2024-now. Omit summary_field to label spans "Version 1", "Version
        2", etc. instead. The record's current version (if it still exists)
        has no end date, drawn through to today.

        Same identifying-field resolution as record_history: form_type,
        questionclass, value.
      DESCRIPTION

      INPUT_SCHEMA = {
        type: 'object',
        properties: {
          form_type: { type: 'string' },
          questionclass: { type: 'string' },
          value: { type: 'string' },
          summary_field: { type: 'string', description: 'Optional questionclass to label each span with' }
        },
        required: %w[form_type questionclass value]
      }.freeze

      def self.call(arguments)
        form_type = arguments['form_type']
        primary_id = find_primary_id(form_type: form_type, questionclass: arguments['questionclass'], value: arguments['value'])
        unless primary_id
          raise "No #{form_type} record found with #{arguments['questionclass']} = #{arguments['value'].inspect}"
        end

        versions = full_timeline(form_type: form_type, primary_id: primary_id)
        rows = versions.each_with_index.map { |v, i| timeline_row(v, i, arguments['summary_field']) }

        [{ type: 'text', text: rows.to_json }]
      end

      def self.timeline_row(version, index, summary_field)
        label = summary_field && !summary_field.to_s.empty? ? Array(snapshot_fields(triples: version[:triples])[summary_field]).join(', ') : nil
        label = "Version #{index + 1}" if label.to_s.strip.empty?

        row = { label: label, start: version[:generated_at] }
        row[:end] = version[:invalidated_at] if version[:invalidated_at]
        row
      end
      private_class_method :timeline_row
    end
  end
end
