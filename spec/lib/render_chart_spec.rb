# frozen_string_literal: true

require 'rexml/document'

# McpTools::Shared::RenderChart (lib/mcp_tools/shared/render_chart.rb) -
# renders a hand-built SVG (no charting gem) plus the underlying data as a
# text block, so the result degrades gracefully if the client doesn't
# render images. These specs check the output is well-formed XML and
# contains the expected number of marks, not exact pixel positions.
RSpec.describe McpTools::Shared::RenderChart do
  def rows_for(chart_type)
    case chart_type
    when 'bar', 'scatter'
      [{ 'type' => 'European', 'amount' => '100' }, { 'type' => 'National', 'amount' => '50' }]
    when 'line'
      [{ 'year' => '2021', 'amount' => '10' }, { 'year' => '2022', 'amount' => '25' }, { 'year' => '2023', 'amount' => '15' }]
    end
  end

  def call_and_decode(chart_type, x_field:, y_field:)
    result = described_class.call({
                                     'rows' => rows_for(chart_type), 'chart_type' => chart_type,
                                     'x_field' => x_field, 'y_field' => y_field, 'title' => 'Test chart'
                                   })
    { image: result.find { |c| c[:type] == 'image' }, text: result.find { |c| c[:type] == 'text' } }
  end

  %w[bar scatter line].each do |chart_type|
    it "returns a well-formed SVG image content block for chart_type=#{chart_type}" do
      content = call_and_decode(chart_type, x_field: chart_type == 'line' ? 'year' : 'type', y_field: 'amount')
      expect(content[:image][:mimeType]).to eq('image/svg+xml')

      svg = Base64.decode64(content[:image][:data])
      expect { REXML::Document.new(svg) }.not_to raise_error
      expect(svg).to include('<svg')
      expect(svg).to include('Test chart')
    end

    it "also returns the underlying rows as a text block for chart_type=#{chart_type}" do
      content = call_and_decode(chart_type, x_field: chart_type == 'line' ? 'year' : 'type', y_field: 'amount')
      expect(JSON.parse(content[:text][:text])).to eq(rows_for(chart_type))
    end
  end

  it 'escapes a label containing XML-significant characters so the SVG stays well-formed' do
    result = described_class.call({
                                     'rows' => [{ 'type' => 'R&D <special>', 'amount' => '10' }],
                                     'chart_type' => 'bar', 'x_field' => 'type', 'y_field' => 'amount'
                                   })
    svg = Base64.decode64(result.first[:data])
    expect { REXML::Document.new(svg) }.not_to raise_error
    expect(svg).to include('R&amp;D &lt;special&gt;')
  end

  it 'raises on an unrecognized chart_type rather than silently returning something' do
    expect do
      described_class.call({ 'rows' => [], 'chart_type' => 'pie', 'x_field' => 'a', 'y_field' => 'b' })
    end.to raise_error(ArgumentError)
  end

  describe 'chart_type "timeline"' do
    def timeline_rows
      [
        { 'label' => 'Predoctoral', 'start' => '2018-01-01', 'end' => '2021-06-30' },
        { 'label' => 'Postdoctoral', 'start' => '2021-07-01', 'end' => '2024-01-01' },
        { 'label' => 'Staff Scientist', 'start' => '2024-01-01' } # no end = ongoing
      ]
    end

    def timeline_svg(rows, **extra)
      result = described_class.call({ 'rows' => rows, 'chart_type' => 'timeline', 'title' => 'Career timeline' }.merge(extra))
      Base64.decode64(result.first[:data])
    end

    it 'returns a well-formed SVG with one bar per dated row, growing height with row count' do
      svg = timeline_svg(timeline_rows)
      expect { REXML::Document.new(svg) }.not_to raise_error
      expect(svg.scan('<rect').size).to eq(4) # 3 spans + 1 background
      expect(svg).to include('Predoctoral')
      expect(svg).to include('Staff Scientist')
    end

    it 'draws an ongoing (no end date) row through to today rather than omitting it' do
      svg = timeline_svg([{ 'label' => 'Still active', 'start' => '2024-01-01' }])
      expect { REXML::Document.new(svg) }.not_to raise_error
      expect(svg).to include('Still active')
    end

    it 'skips a row with no parseable start date rather than raising' do
      svg = timeline_svg([{ 'label' => 'Bad row', 'start' => 'not-a-date' },
                           { 'label' => 'Good row', 'start' => '2020-01-01', 'end' => '2021-01-01' }])
      expect(svg).not_to include('Bad row')
      expect(svg).to include('Good row')
    end

    it 'renders a friendly empty-state SVG rather than crashing when no rows have a parseable date' do
      svg = timeline_svg([{ 'label' => 'x', 'start' => 'garbage' }])
      expect { REXML::Document.new(svg) }.not_to raise_error
      expect(svg).to include('No dated rows to plot')
    end

    it 'honors custom label_field/start_field/end_field names' do
      rows = [{ 'who' => 'A Project', 'began' => '2020-01-01', 'ended' => '2022-01-01' }]
      svg = timeline_svg(rows, 'label_field' => 'who', 'start_field' => 'began', 'end_field' => 'ended')
      expect(svg).to include('A Project')
    end

    it 'still returns the raw rows as a text block' do
      result = described_class.call({ 'rows' => timeline_rows, 'chart_type' => 'timeline' })
      expect(JSON.parse(result.last[:text])).to eq(timeline_rows)
    end
  end
end
