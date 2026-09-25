# frozen_string_literal: true

require 'base64'
require 'date'
require 'json'

module McpTools
  module Shared
    # MCP tool: renders a table of rows (from search_records,
    # aggregate_over_time, record_timeline, ...) as a chart. Returns both
    # an "image" content block (a hand-built SVG, base64-encoded - no
    # charting gem or native dependency) and a "text" block with the same
    # underlying data, so the result degrades gracefully to plain numbers if
    # the MCP client doesn't render images inline.
    class RenderChart
      NAME = 'render_chart'

      DESCRIPTION = <<~DESCRIPTION
        Renders a table of rows you already have (from search_records,
        aggregate_over_time, record_timeline, or any other tool's output) as
        a chart - never queries the database itself.

        chart_type "bar": one bar per row, x_field labels the bars, y_field
          is the bar height. Good for "funding by type" (x_field
          "project_type", y_field "total_funding").
        chart_type "scatter": one point per row, x_field/y_field are both
          numeric. Good for a correlation question, e.g. funding vs.
          Q1-publication count.
        chart_type "line": points in x_field order connected by a line. Good
          for a trend over years (x_field "year", y_field "total_funding").
        chart_type "timeline": one horizontal bar per row spanning
          start_field..end_field (a Gantt-style view) - label_field names
          each bar. Reusable for a single career/project history (rows =
          that one record's versions or milestones) or an institute-wide
          view (rows = many records' whole lifespans at once). Omit a row's
          end value for a still-ongoing span - it's drawn through to today.
          record_timeline's output is already shaped for this directly.
        chart_type "stacked_bar": for a THIRD dimension on top of bar's
          two - x_field groups the bars (e.g. "year"), y_field is the
          value, and series_field splits each x-group into multiple
          colored segments (e.g. "project_type"). aggregate_over_time's
          {bucket, group, value} rows plug into this directly
          (x_field "bucket", y_field "value", series_field "group").
          mode "stacked" (default) stacks segments to show both each
          series' contribution and the total - the right choice for "how
          has the budget split by funding type changed over the years".
          mode "grouped" places them side by side instead - better for
          directly comparing series against each other rather than the
          total, e.g. comparing a metric across two scenarios.

        Returns the chart as an image AND the same rows as text, so the
        numbers are always available even if the image doesn't render.
      DESCRIPTION

      INPUT_SCHEMA = {
        type: 'object',
        properties: {
          rows: { type: 'array', items: { type: 'object' } },
          chart_type: { type: 'string', enum: %w[bar scatter line timeline stacked_bar] },
          x_field: { type: 'string', description: 'Required for bar/scatter/line/stacked_bar' },
          y_field: { type: 'string', description: 'Required for bar/scatter/line/stacked_bar' },
          series_field: { type: 'string', description: 'Required for stacked_bar - splits each x-group into colored segments' },
          mode: { type: 'string', enum: %w[stacked grouped], description: 'For stacked_bar - default "stacked"' },
          label_field: { type: 'string', description: 'For timeline - default "label"' },
          start_field: { type: 'string', description: 'For timeline - default "start"' },
          end_field: { type: 'string', description: 'For timeline - default "end"; a row may omit this value for an ongoing span' },
          title: { type: 'string' }
        },
        required: %w[rows chart_type]
      }.freeze

      SERIES_PALETTE = %w[#3d6650 #b8792f #6b7fb0 #a35d6a #7a9c5e #c4934a #5c8a99 #9c7ab0].freeze

      WIDTH = 640
      HEIGHT = 400
      MARGIN = { top: 40, right: 24, bottom: 56, left: 64 }.freeze
      TIMELINE_MARGIN = { top: 40, right: 24, bottom: 40, left: 180 }.freeze
      TIMELINE_ROW_HEIGHT = 28

      def self.call(arguments)
        rows = arguments['rows'] || []
        chart_type = arguments['chart_type']

        svg =
          case chart_type
          when 'timeline'
            build_timeline_svg(
              rows: rows,
              label_field: arguments['label_field'] || 'label',
              start_field: arguments['start_field'] || 'start',
              end_field: arguments['end_field'] || 'end',
              title: arguments['title']
            )
          when 'stacked_bar'
            build_stacked_bar_svg(
              rows: rows, x_field: arguments['x_field'], y_field: arguments['y_field'],
              series_field: arguments['series_field'], mode: arguments['mode'] || 'stacked', title: arguments['title']
            )
          else
            build_svg(
              rows: rows, chart_type: chart_type,
              x_field: arguments['x_field'], y_field: arguments['y_field'], title: arguments['title']
            )
          end

        [
          { type: 'image', mimeType: 'image/svg+xml', data: Base64.strict_encode64(svg) },
          { type: 'text', text: rows.to_json }
        ]
      end

      def self.build_svg(rows:, chart_type:, x_field:, y_field:, title:)
        raise ArgumentError, 'x_field and y_field are required for this chart_type' if x_field.to_s.empty? || y_field.to_s.empty?

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

        <<~SVG
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{WIDTH} #{HEIGHT}" font-family="sans-serif">
            <rect width="#{WIDTH}" height="#{HEIGHT}" fill="#ffffff" />
            #{title_svg(title, WIDTH)}
            #{axes_svg(plot_width, plot_height, y_min, y_max, y_to_px)}
            #{marks}
          </svg>
        SVG
      end
      private_class_method :build_svg

      def self.title_svg(title, width)
        return '' unless title

        %(<text x="#{width / 2}" y="20" text-anchor="middle" font-size="15" font-weight="600" fill="#1c2620">#{escape_xml(title)}</text>)
      end
      private_class_method :title_svg

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

      ##########################################################################
      # Stacked/grouped bar - a third dimension (series_field) on top of
      # plain bar's two. Shares the same fixed-height/numeric-y-axis layout
      # as build_svg above, but the y-scale and each bar's geometry depend
      # on how values pivot across (x_field, series_field), so it isn't a
      # simple case branch inside bar_marks.
      ##########################################################################

      def self.build_stacked_bar_svg(rows:, x_field:, y_field:, series_field:, mode:, title:)
        if [x_field, y_field, series_field].any? { |f| f.to_s.empty? }
          raise ArgumentError, 'x_field, y_field, and series_field are all required for stacked_bar'
        end

        categories, series, totals = pivot(rows, x_field, y_field, series_field)
        plot_width = WIDTH - MARGIN[:left] - MARGIN[:right]
        plot_height = HEIGHT - MARGIN[:top] - MARGIN[:bottom] - 20 # legend row

        y_max = mode == 'grouped' ? (totals.values.flat_map(&:values).max || 1) : (totals.values.map { |h| h.values.sum }.max || 1)
        y_max = 1 if y_max.zero?
        y_to_px = ->(y) { MARGIN[:top] + plot_height - (y.to_f / y_max * plot_height) }

        bars = stacked_bar_marks(categories, series, totals, mode, plot_width, y_to_px)

        <<~SVG
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{WIDTH} #{HEIGHT}" font-family="sans-serif">
            <rect width="#{WIDTH}" height="#{HEIGHT}" fill="#ffffff" />
            #{title_svg(title, WIDTH)}
            #{axes_svg(plot_width, plot_height, 0, y_max, y_to_px)}
            #{bars}
            #{legend_svg(series, plot_width)}
          </svg>
        SVG
      end
      private_class_method :build_stacked_bar_svg

      # @return [Array(Array<String>, Array<String>, Hash)] categories (x_field
      #   values, first-seen order), series (series_field values, first-seen
      #   order), and totals[category][series] = summed y_field value
      #   (duplicate rows for the same pair are summed, not overwritten)
      def self.pivot(rows, x_field, y_field, series_field)
        categories = []
        series = []
        totals = Hash.new { |h, k| h[k] = Hash.new(0) }

        rows.each do |row|
          category = row[x_field].to_s
          s = row[series_field].to_s
          value = Float(row[y_field], exception: false)
          next unless value

          categories << category unless categories.include?(category)
          series << s unless series.include?(s)
          totals[category][s] += value
        end

        [categories, series, totals]
      end
      private_class_method :pivot

      def self.stacked_bar_marks(categories, series, totals, mode, plot_width, y_to_px)
        return '' if categories.empty?

        colors = series.each_with_index.to_h { |s, i| [s, SERIES_PALETTE[i % SERIES_PALETTE.size]] }
        slot = plot_width / categories.size.to_f
        y0 = MARGIN[:top] + (HEIGHT - MARGIN[:top] - MARGIN[:bottom] - 20)

        categories.each_with_index.map do |category, i|
          x0 = MARGIN[:left] + (i * slot)
          label = %(<text x="#{(x0 + slot / 2).round(1)}" y="#{y0 + 16}" text-anchor="middle" font-size="10" fill="#5b665f">#{escape_xml(category)}</text>)
          segments =
            if mode == 'grouped'
              grouped_segments(category, series, totals, colors, x0, slot, y_to_px, y0)
            else
              stacked_segments(category, series, totals, colors, x0, slot, y_to_px)
            end
          segments + label
        end.join
      end
      private_class_method :stacked_bar_marks

      def self.stacked_segments(category, series, totals, colors, x0, slot, y_to_px)
        bar_width = slot * 0.65
        x = x0 + ((slot - bar_width) / 2)
        cumulative = 0
        series.filter_map do |s|
          value = totals[category][s]
          next if value.zero?

          top = y_to_px.call(cumulative + value)
          bottom = y_to_px.call(cumulative)
          cumulative += value
          %(<rect x="#{x.round(1)}" y="#{top.round(1)}" width="#{bar_width.round(1)}" height="#{(bottom - top).round(1)}" fill="#{colors[s]}" />)
        end.join
      end
      private_class_method :stacked_segments

      def self.grouped_segments(category, series, totals, colors, x0, slot, y_to_px, y0)
        present = series.reject { |s| totals[category][s].zero? }
        return '' if present.empty?

        sub_width = (slot * 0.8) / present.size
        present.each_with_index.map do |s, j|
          value = totals[category][s]
          x = x0 + (slot * 0.1) + (j * sub_width)
          py = y_to_px.call(value)
          %(<rect x="#{x.round(1)}" y="#{py.round(1)}" width="#{(sub_width * 0.9).round(1)}" height="#{(y0 - py).round(1)}" fill="#{colors[s]}" />)
        end.join
      end
      private_class_method :grouped_segments

      def self.legend_svg(series, plot_width)
        return '' if series.empty?

        y = HEIGHT - 12
        x = MARGIN[:left]
        swatch = 10
        gap = 14
        series.each_with_index.map do |s, i|
          color = SERIES_PALETTE[i % SERIES_PALETTE.size]
          label_width = [s.length * 6 + gap + swatch + 10, 40].max
          sx = x
          x += label_width
          next if x > plot_width + MARGIN[:left] + 40 # don't overflow the canvas on many series

          <<~SVG
            <rect x="#{sx}" y="#{y - swatch}" width="#{swatch}" height="#{swatch}" fill="#{color}" />
            <text x="#{sx + swatch + 4}" y="#{y}" font-size="10" fill="#1c2620">#{escape_xml(s)}</text>
          SVG
        end.join
      end
      private_class_method :legend_svg

      ##########################################################################
      # Timeline (Gantt-style) - a fundamentally different layout from the
      # numeric-y-axis charts above: the x-axis is TIME, the y-axis is one
      # categorical lane per row, and the image height grows with the number
      # of rows rather than being fixed.
      ##########################################################################

      def self.build_timeline_svg(rows:, label_field:, start_field:, end_field:, title:)
        spans = timeline_spans(rows, label_field, start_field, end_field)
        height = TIMELINE_MARGIN[:top] + TIMELINE_MARGIN[:bottom] + ([spans.size, 1].max * TIMELINE_ROW_HEIGHT)
        plot_width = WIDTH - TIMELINE_MARGIN[:left] - TIMELINE_MARGIN[:right]

        return empty_timeline_svg(height, title) if spans.empty?

        min_date = spans.map { |s| s[:start] }.min
        max_date = spans.map { |s| s[:end] }.max
        max_date = min_date + 1 if max_date <= min_date

        x_to_px = ->(d) { TIMELINE_MARGIN[:left] + ((d - min_date).to_f / (max_date - min_date) * plot_width) }

        lanes = spans.each_with_index.map do |span, i|
          y = TIMELINE_MARGIN[:top] + (i * TIMELINE_ROW_HEIGHT)
          x1 = x_to_px.call(span[:start])
          x2 = x_to_px.call(span[:end])
          bar_height = TIMELINE_ROW_HEIGHT * 0.6
          <<~SVG
            <text x="#{TIMELINE_MARGIN[:left] - 8}" y="#{(y + (TIMELINE_ROW_HEIGHT / 2) + 4).round(1)}" text-anchor="end" font-size="11" fill="#1c2620">#{escape_xml(span[:label])}</text>
            <rect x="#{x1.round(1)}" y="#{(y + ((TIMELINE_ROW_HEIGHT - bar_height) / 2)).round(1)}" width="#{[x2 - x1, 2].max.round(1)}" height="#{bar_height.round(1)}" fill="#{span[:ongoing] ? '#b8792f' : '#3d6650'}" rx="2" />
          SVG
        end.join

        <<~SVG
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{WIDTH} #{height}" font-family="sans-serif">
            <rect width="#{WIDTH}" height="#{height}" fill="#ffffff" />
            #{title_svg(title, WIDTH)}
            #{timeline_axis_svg(plot_width, height, min_date, max_date, x_to_px)}
            #{lanes}
          </svg>
        SVG
      end
      private_class_method :build_timeline_svg

      def self.empty_timeline_svg(height, title)
        <<~SVG
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{WIDTH} #{height}" font-family="sans-serif">
            <rect width="#{WIDTH}" height="#{height}" fill="#ffffff" />
            #{title_svg(title, WIDTH)}
            <text x="#{WIDTH / 2}" y="#{height / 2}" text-anchor="middle" font-size="12" fill="#8a9189">No dated rows to plot</text>
          </svg>
        SVG
      end
      private_class_method :empty_timeline_svg

      # @return [Array<Hash>] {label:, start: Date, end: Date, ongoing: Boolean}
      #   a row with no parseable start is left out entirely; a missing/
      #   unparseable end is treated as "ongoing", drawn through to today
      def self.timeline_spans(rows, label_field, start_field, end_field)
        rows.filter_map do |row|
          start_date = parse_date(row[start_field])
          next unless start_date

          end_raw = row[end_field]
          end_date = parse_date(end_raw)
          ongoing = end_raw.to_s.strip.empty? || end_date.nil?
          end_date ||= Date.today

          { label: row[label_field].to_s, start: start_date, end: end_date, ongoing: ongoing }
        end
      end
      private_class_method :timeline_spans

      def self.parse_date(value)
        return nil if value.to_s.strip.empty?

        Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
      private_class_method :parse_date

      def self.timeline_axis_svg(plot_width, height, min_date, max_date, x_to_px)
        x0 = TIMELINE_MARGIN[:left]
        y0 = height - TIMELINE_MARGIN[:bottom] + TIMELINE_ROW_HEIGHT - 12
        ticks = 4
        span_days = max_date - min_date

        labels = (0..ticks).map do |i|
          d = min_date + (span_days * i / ticks.to_f)
          px = x_to_px.call(d)
          fmt = span_days > 730 ? d.strftime('%Y') : d.strftime('%Y-%m')
          %(<text x="#{px.round(1)}" y="#{y0}" text-anchor="middle" font-size="10" fill="#5b665f">#{fmt}</text>)
        end.join

        %(<line x1="#{x0}" y1="#{y0 - 14}" x2="#{x0 + plot_width}" y2="#{y0 - 14}" stroke="#1c2620" stroke-width="1" />#{labels})
      end
      private_class_method :timeline_axis_svg

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
