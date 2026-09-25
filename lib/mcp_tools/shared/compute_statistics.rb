# frozen_string_literal: true

require 'json'

module McpTools
  module Shared
    # MCP tool: pure arithmetic over a table of rows already returned by
    # another tool call (search_records, aggregate_over_time, ...) - no
    # database access of its own. Exists so a budget-constrained model
    # (Gemini Light) doesn't have to do the actual arithmetic itself over a
    # table of a few dozen rows; it hands the numbers here and gets back a
    # single deterministic result instead.
    class ComputeStatistics
      NAME = 'compute_statistics'

      DESCRIPTION = <<~DESCRIPTION
        Computes a statistic over a table of rows you already have (from
        search_records, aggregate_over_time, or any other tool's output) -
        never queries the database itself. Use this instead of doing the
        arithmetic yourself; it's exact, you aren't.

        Operations:
          correlation - Pearson correlation coefficient between two numeric
            fields (x_field, y_field required). Rows missing either field are
            skipped. Needs at least 3 usable rows.
          mean / sum / count - over one numeric field (field required for
            mean/sum; count works on rows directly). Add group_by to get one
            result per distinct value of another field instead of one overall
            number.
          proportion - fraction of rows where field equals value (both
            required). Add group_by for one proportion per group.

        Example: after calling aggregate_over_time to get
          [{"project_type":"European","year":"2023","total_funding":"450000"}, ...]
        call this with operation "correlation", x_field "total_funding",
        y_field "q1_publication_count" to get a single r value, rather than
        eyeballing the table.
      DESCRIPTION

      INPUT_SCHEMA = {
        type: 'object',
        properties: {
          rows: {
            type: 'array',
            items: { type: 'object' },
            description: 'The table to compute over - an array of flat objects, same shape as another tool returned'
          },
          operation: {
            type: 'string',
            enum: %w[correlation mean sum count proportion]
          },
          x_field: { type: 'string', description: 'Required for correlation' },
          y_field: { type: 'string', description: 'Required for correlation' },
          field: { type: 'string', description: 'Required for mean/sum/proportion' },
          value: { description: 'Required for proportion - the value field must equal' },
          group_by: { type: 'string', description: 'Optional - split the result out per distinct value of this field' }
        },
        required: %w[rows operation]
      }.freeze

      def self.call(arguments)
        rows = arguments['rows'] || []
        operation = arguments['operation']
        group_by = arguments['group_by']

        result =
          if group_by
            rows.group_by { |r| r[group_by] }.transform_values { |group_rows| compute(operation, group_rows, arguments) }
          else
            compute(operation, rows, arguments)
          end

        [{ type: 'text', text: result.to_json }]
      end

      def self.compute(operation, rows, arguments)
        case operation
        when 'correlation' then correlation(rows, arguments['x_field'], arguments['y_field'])
        when 'mean' then mean(rows, arguments['field'])
        when 'sum' then sum(rows, arguments['field'])
        when 'count' then rows.size
        when 'proportion' then proportion(rows, arguments['field'], arguments['value'])
        else raise ArgumentError, "Unknown operation: #{operation.inspect}"
        end
      end
      private_class_method :compute

      def self.numbers(rows, field)
        raise ArgumentError, 'field is required' if field.to_s.empty?

        rows.filter_map { |r| Float(r[field], exception: false) }
      end
      private_class_method :numbers

      def self.mean(rows, field)
        values = numbers(rows, field)
        return nil if values.empty?

        values.sum / values.size
      end
      private_class_method :mean

      def self.sum(rows, field)
        numbers(rows, field).sum
      end
      private_class_method :sum

      def self.proportion(rows, field, value)
        raise ArgumentError, 'field is required' if field.to_s.empty?
        return nil if rows.empty?

        rows.count { |r| r[field].to_s == value.to_s } / rows.size.to_f
      end
      private_class_method :proportion

      # Pearson correlation coefficient. Returns nil (not an error) when
      # there's too little usable data to mean anything, rather than raising
      # or returning a misleading number like 0 or NaN.
      def self.correlation(rows, x_field, y_field)
        raise ArgumentError, 'x_field and y_field are required' if x_field.to_s.empty? || y_field.to_s.empty?

        pairs = rows.filter_map do |r|
          x = Float(r[x_field], exception: false)
          y = Float(r[y_field], exception: false)
          [x, y] if x && y
        end
        return nil if pairs.size < 3

        xs = pairs.map(&:first)
        ys = pairs.map(&:last)
        x_mean = xs.sum / xs.size
        y_mean = ys.sum / ys.size

        numerator = pairs.sum { |x, y| (x - x_mean) * (y - y_mean) }
        x_variance = xs.sum { |x| (x - x_mean)**2 }
        y_variance = ys.sum { |y| (y - y_mean)**2 }
        denominator = Math.sqrt(x_variance * y_variance)

        return nil if denominator.zero?

        { r: (numerator / denominator).round(4), n: pairs.size }
      end
      private_class_method :correlation
    end
  end
end
