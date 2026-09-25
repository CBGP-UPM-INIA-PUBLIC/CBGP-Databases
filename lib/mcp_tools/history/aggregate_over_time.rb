# frozen_string_literal: true

require 'json'

module McpTools
  module History
    # MCP tool: the workhorse for trend questions - "funding by type, by
    # year", "headcount by category, by year", etc. Filters records (same
    # facets/date_ranges shape as temporal_search), buckets what's left by
    # a date field's year or month, optionally groups each bucket by
    # another facet, then reduces each (bucket, group) with count/sum/avg.
    class AggregateOverTime
      NAME = 'aggregate_over_time'

      DESCRIPTION = <<~DESCRIPTION
        Groups and reduces records BY TIME BUCKET (year or month), and
        optionally by another facet at the same time - e.g. "sum
        project_total_funding by project_type, by year" for a funding-trend
        question, or "count members by member_category, by year" for a
        headcount-over-time question.

        facets/date_ranges (same shape as temporal_search) narrow which
        records are considered first. date_field is the questionclass
        bucketed into years/months. group_by (optional) is a second
        questionclass to split each time bucket by. metric is required for
        agg_op sum/avg (the questionclass to reduce); agg_op defaults to
        "count".

        Returns rows already shaped for render_chart or compute_statistics:
        [{"bucket": "2024", "group": "European", "value": 450000.0}, ...]
        (group omitted if group_by wasn't given). For a single trend line,
        render_chart with chart_type "line", x_field "bucket", y_field
        "value" works directly.
      DESCRIPTION

      INPUT_SCHEMA = {
        type: 'object',
        properties: {
          form_type: { type: 'string' },
          date_field: { type: 'string', description: 'questionclass of the date to bucket by' },
          granularity: { type: 'string', enum: %w[year month], description: 'default "year"' },
          group_by: { type: 'string', description: 'Optional second questionclass to group by' },
          metric: { type: 'string', description: 'questionclass to sum/average - required for agg_op sum/avg' },
          agg_op: { type: 'string', enum: %w[count sum avg], description: 'default "count"' },
          facets: { type: 'object' },
          date_ranges: { type: 'object' }
        },
        required: %w[form_type date_field]
      }.freeze

      def self.call(arguments)
        snapshots = filter_snapshots_during(
          form_type: arguments['form_type'],
          facets: arguments['facets'] || {},
          date_ranges: normalized_date_ranges(arguments['date_ranges'])
        )
        buckets = bucket_by_date(
          snapshots: snapshots, date_field: arguments['date_field'], granularity: arguments['granularity'] || 'year'
        )

        rows = buckets.flat_map { |label, bucket_snaps| bucket_rows(label, bucket_snaps, arguments) }
                      .sort_by { |r| r[:bucket] }

        [{ type: 'text', text: rows.to_json }]
      end

      def self.normalized_date_ranges(date_ranges)
        (date_ranges || {}).transform_values { |r| { start: r['start'], end: r['end'] } }
      end
      private_class_method :normalized_date_ranges

      def self.bucket_rows(label, bucket_snaps, arguments)
        agg_op = arguments['agg_op'] || 'count'
        group_by = arguments['group_by']

        if group_by
          grouped = Hash.new { |h, k| h[k] = [] }
          bucket_snaps.each do |snap|
            snapshot_field_values(triples: snap[:triples], questionclass: group_by).each { |g| grouped[g] << snap }
          end
          grouped.map { |group, snaps| { bucket: label, group: group, value: reduce(snaps, arguments['metric'], agg_op) } }
        else
          [{ bucket: label, value: reduce(bucket_snaps, arguments['metric'], agg_op) }]
        end
      end
      private_class_method :bucket_rows

      def self.reduce(snapshots, metric, agg_op)
        case agg_op
        when 'count' then snapshots.size
        when 'sum' then sum_numeric_field(snapshots: snapshots, questionclass: metric).to_f
        when 'avg' then snapshots.empty? ? 0.0 : (sum_numeric_field(snapshots: snapshots, questionclass: metric) / snapshots.size).to_f
        else raise ArgumentError, "Unknown agg_op: #{agg_op.inspect}"
        end
      end
      private_class_method :reduce
    end
  end
end
