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
      LEFT = 200.0 # lane-name gutter: fits "Compromiso de financiación" (26 characters) at 11px bold
      RIGHT = 24.0
      ROW_H = 24
      LANE_MAX = 26
      CHAR_W = 6.4
      LANE_GAP = 26
      AXIS_H = 34
      WORDS = {
        'en' => { ongoing: 'ongoing', today: 'Today', download: 'Download SVG', download_png: 'Download PNG', title: 'Timeline', file: 'timeline', months: %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec] },
        'es' => { ongoing: 'en curso', today: 'Hoy', download: 'Descargar SVG', download_png: 'Descargar PNG', title: 'Cronología', file: 'cronologia', months: %w[ene feb mar abr may jun jul ago sep oct nov dic] }
      }.freeze
      TITLE_H = 30
      FONT = 'system-ui,-apple-system,"Segoe UI","DejaVu Sans",Arial,sans-serif'
      LIGHT = { 'bg' => '#ffffff', 'fg' => '#1c2330', 'muted' => '#6b7585', 'band' => '#f3f5f8', 'grid' => '#dde2ea', 'today' => '#c0392b' }.freeze
      # Colours as variables on the page (so it follows the viewer's dark mode); the
      # shapes' rules below refer to them. The standalone SVG gets the light values.
      VARS = <<~CSS.freeze
        :root{--bg:#fff;--fg:#1c2330;--muted:#6b7585;--band:#f3f5f8;--grid:#dde2ea;--today:#c0392b}
        @media (prefers-color-scheme:dark){:root{--bg:#161b22;--fg:#e6e9ee;--muted:#9aa4b2;--band:#1e252e;--grid:#2c3542;--today:#ff7b6b}}
      CSS
      PAGE = <<~CSS.freeze
        body{margin:0;padding:12px 16px;background:var(--bg);color:var(--fg);font:13px system-ui,sans-serif}
        h1{font-size:16px;margin:0 0 8px}
        .dl{margin:6px 0 0;font-size:12px}.dl a{color:var(--muted)}.dl a+a{margin-left:12px}
      CSS
      RULES = <<~CSS.freeze
        .band{fill:var(--band)}.grid{stroke:var(--grid);stroke-width:1}.axis{stroke:var(--muted);stroke-width:1}
        .today{stroke:var(--today);stroke-width:1.5;stroke-dasharray:4 3}
        .todaylbl{fill:var(--today);font-size:11px;font-weight:600}.tick{fill:var(--muted);font-size:11px}.lane{font-size:11px;font-weight:600}.lbl{fill:var(--fg);font-size:12px}.inbar{fill:#fff}
      CSS
      # The page can make its own PNG, in the viewer's browser: the SVG (carried in
      # the "Download SVG" link) is drawn onto a canvas at twice its size and saved.
      # No server involved, so it needs no converter, no file path and no extra
      # payload. Where scripts are blocked (a sandboxed frame) the link stays hidden
      # and the SVG link still works; in a saved or separately opened page it appears.
      PNG_SCRIPT = <<~JS.freeze
        (function(){
          var svgLink=document.getElementById('dlsvg'), pngLink=document.getElementById('dlpng');
          if(!svgLink||!pngLink||!document.createElement('canvas').getContext) return;
          window.cbgpTimelinePng=function(done){
            var img=new Image();
            img.onload=function(){
              var w=(img.naturalWidth||960)*2, h=(img.naturalHeight||300)*2, c=document.createElement('canvas');
              c.width=w; c.height=h;
              var x=c.getContext('2d'); x.fillStyle='#fff'; x.fillRect(0,0,w,h); x.drawImage(img,0,0,w,h);
              c.toBlob(done,'image/png');
            };
            img.src=svgLink.href;
          };
          pngLink.hidden=false;
          pngLink.addEventListener('click',function(ev){
            ev.preventDefault();
            window.cbgpTimelinePng(function(blob){
              var url=URL.createObjectURL(blob), a=document.createElement('a');
              a.href=url; a.download=pngLink.getAttribute('data-name'); document.body.appendChild(a); a.click(); a.remove();
              setTimeout(function(){URL.revokeObjectURL(url);},2000);
            });
          });
        })();
      JS
      PALETTE = %w[#2a78b5 #b5532a #3a8f5a #8a5ab5 #b58f2a #2a9fa6 #b52a6d #6a7380].freeze

      Row = Struct.new(:label, :start, :end_date, :lane, :detail, :ongoing, :point, keyword_init: true)

      module_function

      # One drawing, three outputs: +html+ (the page: responsive, follows the
      # viewer's dark mode, with a "download SVG" link), +svg+ (a self-contained
      # light-theme file: literal colours, its own styles, a white background and
      # the title drawn in - what the download link carries and what the PNG is
      # made from) .
      #
      # @return [Hash] { html:, svg:, rows:, from:, to:, lanes: }
      def render(rows:, title: nil, today: Date.today, language: 'en')
        parsed = parse_rows(rows, today)
        from = parsed.map(&:start).min
        to = parsed.map { |r| r.end_date || r.start }.max
        from, to = pad(from, to)
        lanes = parsed.map(&:lane).uniq
        language = WORDS.key?(language) ? language : 'en'
        words = WORDS[language]
        drawing = chart(parsed, lanes, from, to, today, words)
        svg = svg_file(drawing, title.to_s, words)
        { html: html_document(drawing, title.to_s, words, language, svg), svg: svg, rows: parsed.size,
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

      # The chart's shapes, without the <svg> wrapper: { inner:, height: }.
      def chart(rows, lanes, from, to, today, words)
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
          body << %(<text class="lane" x="8" y="#{y + 17}" fill="#{color}">#{esc(clip(lane, LANE_MAX))}</text>)
          lane_rows.each_with_index do |row, i|
            body << row_svg(row, x, y + 3 + i * ROW_H, color, words)
          end
          y += height + 6 + LANE_GAP / 2
        end
        plot_bottom = y + 10
        today_visible = today.between?(from, to)
        total_h = plot_bottom + (today_visible ? 14 : 0) # room under the chart for the "Today" label
        axis = axis_svg(from, to, x, plot_bottom, words)
        marker = today_visible ? today_marker(x.(today), plot_bottom, words[:today]) : ''
        { inner: "#{bands}#{axis}#{marker}#{body}", height: total_h }
      end

      def html_document(drawing, title, words, language, svg)
        shown = title.empty? ? words[:title] : title
        heading = title.empty? ? '' : "<h1>#{esc(title)}</h1>"
        links = %(<p class="dl"><a id="dlsvg" download="#{esc(file_name(title, words, 'svg'))}" href="data:image/svg+xml;base64,#{[svg].pack('m0')}">#{esc(words[:download])}</a>) +
                %( <a id="dlpng" data-name="#{esc(file_name(title, words, 'png'))}" href="#" hidden>#{esc(words[:download_png])}</a></p>)
        <<~HTML
          <!doctype html>
          <html lang="#{language}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
          <title>#{esc(shown)}</title>
          <style>#{VARS}#{PAGE}#{RULES}</style></head>
          <body>#{heading}
          <svg viewBox="0 0 #{WIDTH.to_i} #{drawing[:height]}" width="100%" role="img" aria-label="#{esc(shown)}">#{drawing[:inner]}</svg>
          #{links}
          <script>#{PNG_SCRIPT}</script>
          </body></html>
        HTML
      end

      # A standalone SVG: valid on its own (namespace, size, own styles), with
      # literal light-theme colours (no CSS variables or media queries, which
      # editors and rasterizers such as librsvg do not all understand), a white
      # background, and the title drawn into the picture.
      def svg_file(drawing, title, words)
        top = title.empty? ? 0 : TITLE_H
        height = drawing[:height] + top + 4
        heading = title.empty? ? '' : %(<text class="title" x="8" y="20">#{esc(title)}</text>)
        <<~SVG.strip
          <?xml version="1.0" encoding="UTF-8"?>
          <svg xmlns="http://www.w3.org/2000/svg" width="#{WIDTH.to_i}" height="#{height}" viewBox="0 0 #{WIDTH.to_i} #{height}" role="img" aria-label="#{esc(title.empty? ? words[:title] : title)}">
          <style>#{standalone_css}</style>
          <rect width="#{WIDTH.to_i}" height="#{height}" fill="#{LIGHT['bg']}"/>
          #{heading}<g transform="translate(0,#{top})">#{drawing[:inner]}</g>
          </svg>
        SVG
      end

      # A file name for the download, from the title ("alvarez-alfageme-olga.svg").
      def file_name(title, words, extension = 'svg')
        slug = title.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')
        "#{slug.empty? ? words[:file] : slug}.#{extension}"
      end

      # The dashed vertical line for today, labelled so it explains itself;
      # the label sits under the chart and flips to the left near the right edge.
      def today_marker(pos, plot_bottom, word)
        anchor = pos > WIDTH - 60 ? 'end' : 'middle'
        %(<line class="today" x1="#{pos}" x2="#{pos}" y1="#{AXIS_H - 4}" y2="#{plot_bottom - 6}"/>) +
          %(<text class="todaylbl" x="#{pos}" y="#{plot_bottom + 6}" text-anchor="#{anchor}">#{esc(word)}</text>)
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

      def standalone_css
        RULES.gsub(/var\(--(\w+)\)/) { LIGHT.fetch(Regexp.last_match(1)) } +
          "text{font-family:#{FONT}}.title{font-size:16px;font-weight:700;fill:#{LIGHT['fg']}}"
      end
    end
  end
end
