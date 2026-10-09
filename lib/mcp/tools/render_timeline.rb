# frozen_string_literal: true

require 'digest'
require 'base64'
require_relative '../widgets/timeline'
require_relative '../widgets/raster'

module Mcp
  module Tools
    class RenderTimeline < Mcp::Tool
      tool_name 'render_timeline'
      title "Draw timeline"
      summary "Draw a timeline widget (HTML) from dated rows you assembled from other tools. It does not fetch data."
      description <<~TEXT
        Gather the facts first (search_records, linked_records, record_history), then pass them as rows:
        {"label": text, "start": date, "end": date, "lane": group, "ongoing": true, "detail": hover text}.
        label and start are required; dates are YYYY-MM-DD or "today". An end makes a bar; no end makes a point.
        Started and not ended (no end date recorded)? Set "ongoing": true and omit end: the bar runs to today. Never make
        up an end date. Rows with the same lane share a labelled band. Use only dates that appeared in tool results.
        Max 150 rows. Show the returned widget to the user and describe it in a sentence. The widget has "Download SVG"
        and "Download PNG" links for saving the picture, so do NOT set output for that: leave it out (html). Use
        output "png" only if the user explicitly asks for an image attachment instead of the widget.

        Example: render_timeline {"title":"Garcia, Ana","rows":[
          {"lane":"Funding","label":"ALFA 60%","start":"2024-01-01","end":"2025-06-30"},
          {"lane":"Funding","label":"BETA 100%","start":"2025-07-01","ongoing":true},
          {"lane":"Papers","label":"Paper title","start":"2025-03-12"}]}
      TEXT
      param :rows, type: 'array', required: true,
                   description: 'The dated facts to draw, max 150. Use only dates that appeared in tool results.',
                   items: {
                     type: 'object',
                     properties: {
                       label: { type: 'string', description: 'Text shown on the row' },
                       start: { type: 'string', description: 'YYYY-MM-DD (or "today")' },
                       end: { type: 'string', description: 'YYYY-MM-DD. Omit if there is none: a point, or with ongoing a bar to today' },
                       lane: { type: 'string', description: 'Band the row belongs to, e.g. "Funding", "Projects", "Papers"' },
                       ongoing: { type: 'boolean', description: 'true = started and not ended; bar runs to today. Never invent an end date' },
                       detail: { type: 'string', description: 'Hover text' }
                     },
                     required: %w[label start]
                   }
      param :title, type: 'string', description: 'Heading shown above the timeline'
      param :output, type: 'string', enum: %w[html png both],
                     description: 'html (default): the interactive widget, which has Download SVG / Download PNG links. png: a PNG image attachment instead. both: widget plus PNG. Leave it out unless the user explicitly asks for an image attachment'

      OUTPUTS = %w[html png both].freeze

      def self.run(args)
        output = (args['output'] || 'html').to_s.strip.downcase
        raise ToolError, "output must be one of: #{OUTPUTS.join(', ')}." unless OUTPUTS.include?(output)

        drawn = Widgets::Timeline.render(rows: args['rows'], title: args['title'], language: current_language)
        png = Widgets::Raster.png(drawn[:svg]) if %w[both png].include?(output)
        with_html = !(output == 'png' && png) # the widget stays unless a PNG alone was asked for AND made
        blocks = []
        blocks << html_block(drawn[:html]) if with_html
        blocks << { type: 'image', data: Base64.strict_encode64(png), mimeType: 'image/png' } if png
        summary = { drawn: drawn[:rows], from: drawn[:from], to: drawn[:to], lanes: drawn[:lanes],
                    attached: { html: with_html, png: !png.nil? }, note: note_for(output, png) }
        Result.new(summary, blocks)
      end

      def self.html_block(html)
        { type: 'resource', resource: { uri: "ui://timeline/#{Digest::SHA1.hexdigest(html)[0, 12]}", mimeType: 'text/html', text: html } }
      end

      def self.note_for(output, png)
        saving = 'The widget has "Download SVG" and "Download PNG" links for saving the picture.'
        return 'The picture is attached as a PNG image. If you cannot display it, describe these rows in text instead.' if output == 'png' && png
        return "The widget is attached as an HTML resource, and as a PNG image. #{saving} If you cannot display it, describe these rows in text instead." if png

        missing = output == 'png' ? ' A PNG could not be made on this server, so the HTML widget is attached instead.' : ''
        "The widget is attached as an HTML resource.#{missing} #{saving} If you cannot display it, describe these rows in text instead."
      end
    end
  end
end
