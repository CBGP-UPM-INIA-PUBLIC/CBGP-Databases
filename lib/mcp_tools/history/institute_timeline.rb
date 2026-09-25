# frozen_string_literal: true

require 'json'

module McpTools
  module History
    # MCP tool: an institute-wide timeline - one row per record of a
    # form_type, spanning its whole lifetime (creation to now, or to when
    # it was deleted), ready for render_chart's "timeline" chart_type
    # directly. Same underlying primitives as record_timeline, but across
    # every matching record at once instead of one record's own internal
    # versions - "show every project active over the years" or "show every
    # member's tenure at a glance".
    class InstituteTimeline
      NAME = 'institute_timeline'

      DESCRIPTION = <<~DESCRIPTION
        Builds an institute-wide timeline: one row per record of a
        form_type, spanning its whole lifetime - ready for render_chart's
        "timeline" chart_type directly. Good for "show every project active
        over the years" or "show every member's tenure at once" - a
        Gantt-style overview, not one record's internal edit history (use
        record_timeline for that).

        Pass summary_field (a questionclass) to label each row with that
        field's current/last-known value (e.g. "project_type") instead of
        just the record's primary_id. Optional facets/date_ranges narrow
        which records are included (same shape as temporal_search) - e.g.
        facets: {"project_type": "European"} to show only EC-funded
        projects' timelines.
      DESCRIPTION

      INPUT_SCHEMA = {
        type: 'object',
        properties: {
          form_type: { type: 'string' },
          summary_field: { type: 'string', description: 'Optional questionclass to label each row with' },
          facets: { type: 'object' },
          date_ranges: { type: 'object' }
        },
        required: ['form_type']
      }.freeze

      def self.call(arguments)
        form_type = arguments['form_type']
        snapshots = filter_snapshots_during(
          form_type: form_type,
          facets: arguments['facets'] || {},
          date_ranges: normalized_date_ranges(arguments['date_ranges'])
        )

        rows = snapshots.filter_map { |snap| timeline_row(form_type, snap, arguments['summary_field']) }

        [{ type: 'text', text: rows.to_json }]
      end

      def self.normalized_date_ranges(date_ranges)
        (date_ranges || {}).transform_values { |r| { start: r['start'], end: r['end'] } }
      end
      private_class_method :normalized_date_ranges

      def self.timeline_row(form_type, snap, summary_field)
        versions = full_timeline(form_type: form_type, primary_id: snap[:primary_id])
        return nil if versions.empty?

        first_version = versions.first
        last_version = versions.last
        label = row_label(last_version, summary_field, snap[:primary_id])

        row = { label: label, start: first_version[:generated_at], primary_id: snap[:primary_id] }
        row[:end] = last_version[:invalidated_at] if last_version[:invalidated_at]
        row
      end
      private_class_method :timeline_row

      def self.row_label(last_version, summary_field, primary_id)
        return primary_id if summary_field.to_s.empty?

        value = Array(snapshot_fields(triples: last_version[:triples])[summary_field]).join(', ')
        value.strip.empty? ? primary_id : value
      end
      private_class_method :row_label
    end
  end
end
