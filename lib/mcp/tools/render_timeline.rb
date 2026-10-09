# frozen_string_literal: true

require 'digest'
require_relative '../widgets/timeline'

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
        Max 150 rows. Show the returned widget to the user and describe it in a sentence.

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

      def self.run(args)
        drawn = Widgets::Timeline.render(rows: args['rows'], title: args['title'], language: current_language)
        summary = { drawn: drawn[:rows], from: drawn[:from], to: drawn[:to], lanes: drawn[:lanes],
                    note: 'The widget is attached as an HTML resource. If you cannot display it, describe these rows in text instead.' }
        widget = { type: 'resource',
                   resource: { uri: "ui://timeline/#{Digest::SHA1.hexdigest(drawn[:html])[0, 12]}", mimeType: 'text/html', text: drawn[:html] } }
        Result.new(summary, [widget])
      end
    end
  end
end
