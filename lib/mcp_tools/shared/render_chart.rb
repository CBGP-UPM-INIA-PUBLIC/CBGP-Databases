# frozen_string_literal: true

require 'base64'
require 'json'

module McpTools
  module Shared
    # MCP tool: renders a table of rows (from search_records,
    # aggregate_over_time, compute_statistics, ...) as a chart. Returns both
    # an "image" content block (a hand-built SVG, base64-encoded - no
    # charting gem or native dependency) and a "text" block with the same
    # underlying data, so the result degrades gracefully to plain numbers if
    # the MCP client doesn't render images inline.
    class RenderChart
      NAME = 'render_chart'

      DESCRIPTION = <<~DESCRIPTION
        Renders a table of rows you already have (from search_records,
        aggregate_over_time, or any other tool's output) as a chart - never
        queries the database itself.

        chart_type "bar": one bar per row, x_field labels the bars, y_field
          is the bar height. Good for "funding by type" (x_field
          "project_type", y_field "total_funding").
        chart_type "scatter": one point per row, x_field/y_field are both
          numeric. Good for a correlation question, e.g. funding vs.
          Q1-publication count.
        chart_type "line": points in x_field order connected by a line. Good
          for a trend over years (x_field "year", y_field "total_funding").

        Returns the chart as an image AND the same rows as text, so the
        numbers are always available even if the image doesn't render.
      DESCRIPTION

      INPUT_SCHEMA = {
        type: 'object',
        properties: {
          rows: { type: 'array', items: { type: 'object' } },
          chart_type: { type: 'string', enum: %w[bar scatter line] },
          x_field: { type: 'string' },
          y_field: { type: 'string' },
          title: { type: 'string' }
        },
        required: %w[rows chart_type x_field y_field]
      }.freeze

      WIDTH = 640
      HEIGHT = 400
      MARGIN = { top: 40, right: 24, bottom: 56, left: 64 }.freeze

      def self.call(arguments)
        rows = arguments['rows'] || []
        svg = build_svg(
          rows: rows,
          chart_type: arguments['chart_type'],
          x_field: arguments['x_field'],
          y_field: arguments['y_field'],
          title: arguments['title']
        )

        [
          { type: 'image', mimeType: 'image/svg+xml', data: Base64.strict_encode64(svg) },
          { type: 'text', text: rows.to_json }
        ]
      end

      def self.build_svg(rows:, chart_type:, x_field:, y_field:, title:)
        plot_width = WIDTH - MARGIN[:left] - MARGIN[:right]
        plot_height = HEIGHT - MARGIN[:top] - MARGIN[:bottom]

        y_values = rows.filter_map { |r| Float(r[y_field], exception: false) }
        y_min = [y_values.min || 0, 0].min
        y_max = y_values.max || 1
        y_max = y_min + 1 if y_max == y_min

        y_to_px = ->(y) { MARGIN[:top] + plot_height - ((y - y_min).to_f / (y_max - y_min) * plot_height) }

        marks =
          case chart_type
          when 'bar' then bar_marks(rows, x_field, y_field, plot_width, y_to_px)
          when 'scatter' then point_marks(rows, x_field, y_field, plot_width, y_to_px)
          when 'line' then line_marks(rows, x_field, y_field, plot_width, y_to_px)
          else raise ArgumentError, "Unknown chart_type: #{chart_type.inspect}"
          end

        title_svg = title ? %(<text x="#{WIDTH / 2}" y="20" text-anchor="middle" font-size="15" font-weight="600" fill="#1c2620">#{escape_xml(title)}</text>) : ''

        <<~SVG
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{WIDTH} #{HEIGHT}" font-family="sans-serif">
            <rect width="#{WIDTH}" height="#{HEIGHT}" fill="#ffffff" />
            #{title_svg}
            #{axes_svg(plot_width, plot_height, y_min, y_max, y_to_px)}
            #{marks}
          </svg>
        SVG
      end
      private_class_method :build_svg

      def self.axes_svg(plot_width, plot_height, y_min, y_max, y_to_px)
        x0 = MARGIN[:left]
        y0 = MARGIN[:top] + plot_height
        ticks = 4
        gridlines = (0..ticks).map do |i|
          value = y_min + ((y_max - y_min) * i / ticks.to_f)
          py = y_to_px.call(value)
          <<~SVG
            <line x1="#{x0}" y1="#{py}" x2="#{x0 + plot_width}" y2="#{py}" stroke="#e1dcc9" stroke-width="1" />
            <text x="#{x0 - 8}" y="#{py + 4}" text-anchor="end" font-size="11" fill="#5b665f">#{format_number(value)}</text>
          SVG
        end.join

        <<~SVG
          #{gridlines}
          <line x1="#{x0}" y1="#{MARGIN[:top]}" x2="#{x0}" y2="#{y0}" stroke="#1c2620" stroke-width="1" />
          <line x1="#{x0}" y1="#{y0}" x2="#{x0 + plot_width}" y2="#{y0}" stroke="#1c2620" stroke-width="1" />
        SVG
      end
      private_class_method :axes_svg

      def self.bar_marks(rows, x_field, y_field, plot_width, y_to_px)
        return '' if rows.empty?

        slot = plot_width / rows.size.to_f
        bar_width = slot * 0.65
        y0 = MARGIN[:top] + (HEIGHT - MARGIN[:top] - MARGIN[:bottom])

        rows.each_with_index.map do |row, i|
          y_value = Float(row[y_field], exception: false) || 0
          x = MARGIN[:left] + (i * slot) + ((slot - bar_width) / 2)
          py = y_to_px.call(y_value)
          label = escape_xml(row[x_field].to_s)
          <<~SVG
            <rect x="#{x.round(1)}" y="#{py.round(1)}" width="#{bar_width.round(1)}" height="#{(y0 - py).round(1)}" fill="#3d6650" />
            <text x="#{(x + bar_width / 2).round(1)}" y="#{y0 + 16}" text-anchor="middle" font-size="10" fill="#5b665f">#{label}</text>
          SVG
        end.join
      end
      private_class_method :bar_marks

      def self.point_marks(rows, x_field, y_field, plot_width, y_to_px)
        xs = rows.filter_map { |r| Float(r[x_field], exception: false) }
        return '' if xs.empty?

        x_min = [xs.min, 0].min
        x_max = xs.max == x_min ? x_min + 1 : xs.max
        x_to_px = ->(x) { MARGIN[:left] + ((x - x_min).to_f / (x_max - x_min) * plot_width) }

        rows.filter_map do |row|
          x = Float(row[x_field], exception: false)
          y = Float(row[y_field], exception: false)
          next unless x && y

          %(<circle cx="#{x_to_px.call(x).round(1)}" cy="#{y_to_px.call(y).round(1)}" r="4" fill="#b8792f" fill-opacity="0.85" />)
        end.join
      end
      private_class_method :point_marks

      def self.line_marks(rows, x_field, y_field, plot_width, y_to_px)
        points = point_coords(rows, x_field, y_field, plot_width, y_to_px)
        return '' if points.size < 2

        path = points.each_with_index.map { |(x, y), i| "#{i.zero? ? 'M' : 'L'}#{x.round(1)},#{y.round(1)}" }.join(' ')
        dots = points.map { |x, y| %(<circle cx="#{x.round(1)}" cy="#{y.round(1)}" r="3" fill="#3d6650" />) }.join
        %(<path d="#{path}" fill="none" stroke="#3d6650" stroke-width="2" />#{dots})
      end
      private_class_method :line_marks

      def self.point_coords(rows, x_field, y_field, plot_width, y_to_px)
        return [] if rows.empty?

        slot = plot_width / [rows.size - 1, 1].max.to_f
        rows.each_with_index.filter_map do |row, i|
          y = Float(row[y_field], exception: false)
          next unless y

          [MARGIN[:left] + (i * slot), y_to_px.call(y)]
        end
      end
      private_class_method :point_coords

      def self.format_number(value)
        value == value.to_i ? value.to_i.to_s : value.round(2).to_s
      end
      private_class_method :format_number

      def self.escape_xml(str)
        str.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
      end
      private_class_method :escape_xml
    end
  end
end
