# frozen_string_literal: true

require 'json'

module McpTools
  module Core
    # MCP tool: generic group-by aggregation over the core database's
    # CURRENT state - not filtered/rewritten per question, the same
    # search+fetch machinery as search_records, just grouped and reduced in
    # Ruby afterward. For a question that needs the state as of a past
    # date, or a trend over time, use the History server's
    # aggregate_over_time instead - this only ever sees today's data.
    class Aggregate
      NAME = 'aggregate'

      DESCRIPTION = <<~DESCRIPTION
        Groups and reduces core-database records - e.g. "count members by
        member_status" (group_by "member_status", agg_op "count"), or
        "total funding by project type" (group_by "project_type", metric
        "project_total_funding", agg_op "sum"). Call list_form_facets first
        for the exact questionclass identifiers.

        Optional search_params (same shape as search_records) filters which
        records are included before grouping; omit it to aggregate over
        every record of that form_type.

        Only sees the CURRENT state of the database. For a trend over time,
        or the state as of a past date, use the History server's
        aggregate_over_time / point_in_time_snapshot instead.

        Returns {group_value => number}. Feed this straight into
        render_chart (chart_type "bar") to visualize it.
      DESCRIPTION

      INPUT_SCHEMA = {
        type: 'object',
        properties: {
          form_type: { type: 'string' },
          search_params: { type: 'object', description: 'Optional filter, same shape as search_records' },
          group_by: { type: 'string', description: 'questionclass to group on' },
          metric: { type: 'string', description: 'questionclass to sum/average - required for agg_op sum/avg' },
          agg_op: { type: 'string', enum: %w[count sum avg], description: 'default "count"' }
        },
        required: %w[form_type group_by]
      }.freeze

      def self.call(arguments)
        form_type = arguments['form_type']
        search_params = arguments['search_params'] || {}
        group_by = arguments['group_by']
        metric = arguments['metric']
        agg_op = arguments['agg_op'] || 'count'

        graph_uris = execute_search(dataset_type: form_type, search_params: search_params)
        raw_records = fetch_datasets_raw_data(graph_uris: graph_uris, database: form_type)

        groups = Hash.new { |h, k| h[k] = [] }
        raw_records.each { |record| Array(record[group_by.to_sym]).each { |key| groups[key] << record } }

        result = groups.transform_values { |records| aggregate_group(records, metric, agg_op) }
        [{ type: 'text', text: result.to_json }]
      end

      def self.aggregate_group(records, metric, agg_op)
        case agg_op
        when 'count' then records.size
        when 'sum' then numeric_values(records, metric).sum
        when 'avg'
          values = numeric_values(records, metric)
          values.empty? ? nil : values.sum / values.size
        else raise ArgumentError, "Unknown agg_op: #{agg_op.inspect}"
        end
      end
      private_class_method :aggregate_group

      def self.numeric_values(records, metric)
        raise ArgumentError, 'metric is required for agg_op sum/avg' if metric.to_s.empty?

        records.filter_map { |r| Float(Array(r[metric.to_sym]).first, exception: false) }
      end
      private_class_method :numeric_values
    end
  end
end
