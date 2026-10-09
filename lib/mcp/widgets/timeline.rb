# frozen_string_literal: true

require 'cgi'
require 'date'
require_relative '../tool'

module Mcp
  module Widgets
    # A self-contained HTML/SVG timeline (no scripts, no external files) for
    # rows of { label, start, end, lane }. It knows nothing about what the
    # rows mean: any tool's output that can be put into that shape can be
    # drawn. Lanes are horizontal bands (in order of first appearance); a row
    # with an end date is a bar, one without is a point - unless it is marked
    # ongoing, when the bar runs to today.
    module Timeline
      MAX_ROWS = 150
      WIDTH = 960.0
      LEFT = 150.0
      RIGHT = 24.0
      ROW_H = 24
      CHAR_W = 6.4
      LANE_GAP = 26
      AXIS_H = 34
      WORDS = {
        'en' => { ongoing: 'ongoing', title: 'Timeline', months: %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec] },
        'es' => { ongoing: 'en curso', title: 'Cronología', months: %w[ene feb mar abr may jun jul ago sep oct nov dic] }
      }.freeze
      PALETTE = %w[#2a78b5 #b5532a #3a8f5a #8a5ab5 #b58f2a #2a9fa6 #b52a6d #6a7380].freeze

      Row = Struct.new(:label, :start, :end_date, :lane, :detail, :ongoing, :point, keyword_init: true)

      module_function

      # @return [Hash] { html:, rows:, from:, to:, lanes: }
      def render(rows:, title: nil, today: Date.today, language: 'en')
        parsed = parse_rows(rows, today)
        from = parsed.map(&:start).min
        to = parsed.map { |r| r.end_date || r.start }.max
        from, to = pad(from, to)
        lanes = parsed.map(&:lane).uniq
        { html: document(parsed, lanes, from, to, title.to_s, today, WORDS.key?(language) ? language : 'en'), rows: parsed.size,
          from: from.iso8601, to: to.iso8601, lanes: lanes }
      end

      def parse_rows(rows, today)
        raise ToolError, 'rows must be a non-empty list of {label, start, end, lane}.' unless rows.is_a?(Array) && !rows.empty?
        raise ToolError, "At most #{MAX_ROWS} rows can be drawn; filter first (got #{rows.size})." if rows.size > MAX_ROWS

        rows.each_with_index.map do |row, i|
          raise ToolError, "Row #{i + 1} must be an object with label and start." unless row.is_a?(Hash)

          label = row['label'].to_s.strip
          raise ToolError, "Row #{i + 1} has no label." if label.empty?

          start = parse_date(row['start'], "row #{i + 1} start", today)
          raise ToolError, "Row #{i + 1} (#{label}) has no valid start date." unless start

          finish = blank?(row['end']) ? nil : parse_date(row['end'], "row #{i + 1} end", today)
          raise ToolError, "Row #{i + 1} (#{label}): end is before start." if finish && finish < start

          ongoing = row['ongoing'] == true && finish.nil?
          # An ongoing row runs to today - or, if it has not started yet, begins at its start.
          Row.new(label: label, start: start, end_date: ongoing ? [today, start].max : finish,
                  lane: row['lane'].to_s.strip.then { |l| l.empty? ? 'Events' : l },
                  detail: row['detail'].to_s.strip, ongoing: ongoing, point: finish.nil? && !ongoing)
        end
      end

      def blank?(value)
        value.nil? || value.to_s.strip.empty?
      end

      def parse_date(value, where, today)
        text = value.to_s.strip
        return today if text.casecmp?('today') || text.casecmp?('hoy')

        Date.iso8601(text[0, 10])
      rescue ArgumentError
        raise ToolError, "#{where}: '#{text}' is not a date. Use YYYY-MM-DD (a full timestamp is also accepted) or today."
      end

      def pad(from, to)
        return [from - 15, to + 15] if from == to

        margin = [((to - from) * 0.02).ceil, 1].max
        [from - margin, to + margin]
      end

      def document(rows, lanes, from, to, title, today, language)
        words = WORDS[language]
        span = (to - from).to_f
        x = ->(date) { LEFT + ((date - from).to_f / span) * (WIDTH - LEFT - RIGHT) }
        y = AXIS_H
        bands = +''
        body = +''
        lanes.each_with_index do |lane, li|
          color = PALETTE[li % PALETTE.size]
          lane_rows = rows.select { |r| r.lane == lane }
          height = lane_rows.size * ROW_H
          bands << %(<rect class="band" x="0" y="#{y}" width="#{WIDTH}" height="#{height + 6}"/>)
          body << %(<text class="lane" x="8" y="#{y + 17}" fill="#{color}">#{esc(clip(lane, 20))}</text>)
          lane_rows.each_with_index do |row, i|
            body << row_svg(row, x, y + 3 + i * ROW_H, color, words)
          end
          y += height + 6 + LANE_GAP / 2
        end
        total_h = y + 10
        axis = axis_svg(from, to, x, total_h, words)
        marker = today.between?(from, to) ? %(<line class="today" x1="#{x.(today)}" x2="#{x.(today)}" y1="#{AXIS_H - 4}" y2="#{total_h - 6}"/>) : ''
        heading = title.empty? ? '' : "<h1>#{esc(title)}</h1>"
        <<~HTML
          <!doctype html>
          <html lang="#{language}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
          <title>#{esc(title.empty? ? words[:title] : title)}</title>
          <style>#{css}</style></head>
          <body>#{heading}
          <svg viewBox="0 0 #{WIDTH.to_i} #{total_h}" width="100%" role="img" aria-label="#{esc(title.empty? ? words[:title] : title)}">#{bands}#{axis}#{marker}#{body}</svg>
          </body></html>
        HTML
      end

      def row_svg(row, x, top, color, words)
        mid = top + ROW_H / 2.0 - 2
        tip = esc([row.label, "#{row.start.iso8601}#{row.point ? '' : " → #{row.ongoing ? words[:ongoing] : row.end_date.iso8601}"}", row.detail].reject(&:empty?).join("\n"))
        x1 = x.(row.start)
        if row.point
          shape = %(<polygon points="#{x1},#{mid - 6} #{x1 + 6},#{mid} #{x1},#{mid + 6} #{x1 - 6},#{mid}" fill="#{color}"/>)
          right_x = x1 + 10
          left_x = x1 - 10
          bar_w = 0
        else
          x2 = [x.(row.end_date), x1 + 3].max
          shape = %(<rect x="#{x1}" y="#{mid - 6}" width="#{x2 - x1}" height="12" rx="3" fill="#{color}" opacity=".85"/>)
          shape += %(<path d="M#{x2} #{mid - 6} l8 6 l-8 6z" fill="#{color}"/>) if row.ongoing
          right_x = x2 + (row.ongoing ? 12 : 6)
          left_x = x1 - 6
          bar_w = x2 - x1
        end
        label_x, anchor, css_class, text = place_label(row.label, right_x, left_x, x1, bar_w)
        %(<g><title>#{tip}</title>#{shape}<text class="#{css_class}" x="#{label_x}" y="#{mid + 4}" text-anchor="#{anchor}">#{esc(text)}</text></g>)
      end

      # Where a row's label goes, so it is always readable and never runs into
      # the lane names or off the picture: right of the mark if it fits, else
      # left of it, else inside a long bar, else cut short on the roomier
      # side. (The hover text always carries the full label.)
      def place_label(label, right_x, left_x, bar_start, bar_w)
        text = clip(label, 48)
        width = text.length * CHAR_W
        right_room = WIDTH - RIGHT - right_x
        left_room = left_x - (LEFT + 4)
        if width <= right_room then [right_x, 'start', 'lbl', text]
        elsif width <= left_room then [left_x, 'end', 'lbl', text]
        elsif bar_w >= 120 then [bar_start + 6, 'start', 'lbl inbar', clip_to(text, bar_w - 12)]
        elsif right_room >= left_room then [right_x, 'start', 'lbl', clip_to(text, right_room)]
        else [left_x, 'end', 'lbl', clip_to(text, left_room)]
        end
      end

      def clip_to(text, pixels)
        fit = [(pixels / CHAR_W).floor, 4].max
        text.length <= fit ? text : "#{text[0, fit - 1]}…"
      end

      def axis_svg(from, to, x, total_h, words)
        ticks = +''
        if (to - from) > 800
          (from.year + 1..to.year).each { |yr| ticks << tick(x.(Date.new(yr, 1, 1)), yr.to_s, total_h) }
        else
          cursor = Date.new(from.year, from.month, 1) >> 1
          step = (to - from) > 300 ? 3 : 1
          while cursor <= to
            ticks << tick(x.(cursor), cursor.month == 1 ? cursor.year.to_s : words[:months][cursor.month - 1], total_h)
            cursor >>= step
          end
        end
        %(<line class="axis" x1="#{LEFT}" x2="#{WIDTH - RIGHT}" y1="#{AXIS_H - 8}" y2="#{AXIS_H - 8}"/>#{ticks})
      end

      def tick(pos, text, total_h)
        %(<line class="grid" x1="#{pos}" x2="#{pos}" y1="#{AXIS_H - 8}" y2="#{total_h - 6}"/><text class="tick" x="#{pos}" y="#{AXIS_H - 14}" text-anchor="middle">#{esc(text)}</text>)
      end

      def clip(text, max)
        text.length > max ? "#{text[0, max - 1]}…" : text
      end

      def esc(text)
        CGI.escapeHTML(text.to_s)
      end

      def css
        <<~CSS
          :root{--bg:#fff;--fg:#1c2330;--muted:#6b7585;--band:#f3f5f8;--grid:#dde2ea;--today:#c0392b}
          @media (prefers-color-scheme:dark){:root{--bg:#161b22;--fg:#e6e9ee;--muted:#9aa4b2;--band:#1e252e;--grid:#2c3542;--today:#ff7b6b}}
          body{margin:0;padding:12px 16px;background:var(--bg);color:var(--fg);font:13px system-ui,sans-serif}
          h1{font-size:16px;margin:0 0 8px}
          .band{fill:var(--band)}.grid{stroke:var(--grid);stroke-width:1}.axis{stroke:var(--muted);stroke-width:1}
          .today{stroke:var(--today);stroke-width:1.5;stroke-dasharray:4 3}
          .tick{fill:var(--muted);font-size:11px}.lane{font-size:12px;font-weight:600}.lbl{fill:var(--fg);font-size:12px}.inbar{fill:#fff}
        CSS
      end
    end
  end
end
