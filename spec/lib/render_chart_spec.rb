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

  describe 'chart_type "stacked_bar"' do
    def budget_rows
      [
        { 'bucket' => '2021', 'group' => 'European', 'value' => '120000' },
        { 'bucket' => '2021', 'group' => 'National', 'value' => '60000' },
        { 'bucket' => '2022', 'group' => 'European', 'value' => '200000' },
        { 'bucket' => '2022', 'group' => 'National', 'value' => '45000' },
        { 'bucket' => '2022', 'group' => 'Articulo-83', 'value' => '30000' },
        { 'bucket' => '2023', 'group' => 'European', 'value' => '90000' },
        { 'bucket' => '2023', 'group' => 'National', 'value' => '80000' }
      ]
    end

    def stacked_bar_svg(rows, **extra)
      result = described_class.call({ 'rows' => rows, 'chart_type' => 'stacked_bar', 'x_field' => 'bucket',
                                       'y_field' => 'value', 'series_field' => 'group', 'title' => 'Budget' }.merge(extra))
      Base64.decode64(result.first[:data])
    end

    it 'draws one segment per (x, series) pair, well-formed, in "stacked" (default) mode' do
      svg = stacked_bar_svg(budget_rows)
      expect { REXML::Document.new(svg) }.not_to raise_error
      expect(svg.scan('<rect').size).to eq(1 + 7 + 3) # background + 7 data segments + 3 legend swatches
      expect(svg).to include('2021').and include('2022').and include('2023')
      expect(svg).to include('European').and include('National').and include('Articulo-83')
    end

    it 'also draws one segment per pair in "grouped" mode, same counts, different geometry' do
      svg = stacked_bar_svg(budget_rows, 'mode' => 'grouped')
      expect { REXML::Document.new(svg) }.not_to raise_error
      expect(svg.scan('<rect').size).to eq(1 + 7 + 3)
    end

    it 'sums duplicate (x, series) rows rather than overwriting or double-drawing them oddly' do
      rows = [
        { 'bucket' => '2021', 'group' => 'European', 'value' => '50' },
        { 'bucket' => '2021', 'group' => 'European', 'value' => '30' }
      ]
      svg = stacked_bar_svg(rows)
      # one bar segment for the combined (2021, European) pair, not two
      expect(svg.scan('<rect').size).to eq(1 + 1 + 1)
    end

    it 'skips a row with a non-numeric value rather than raising' do
      rows = [{ 'bucket' => '2021', 'group' => 'European', 'value' => 'not-a-number' },
              { 'bucket' => '2021', 'group' => 'National', 'value' => '10' }]
      svg = stacked_bar_svg(rows)
      expect(svg.scan('<rect').size).to eq(1 + 1 + 1)
    end

    it 'renders an empty-but-valid chart when there are no rows' do
      svg = stacked_bar_svg([])
      expect { REXML::Document.new(svg) }.not_to raise_error
    end

    it 'raises when x_field, y_field, or series_field is missing' do
      expect do
        described_class.call({ 'rows' => budget_rows, 'chart_type' => 'stacked_bar', 'x_field' => 'bucket', 'y_field' => 'value' })
      end.to raise_error(ArgumentError)
    end

    it 'still returns the raw rows as a text block' do
      result = described_class.call({ 'rows' => budget_rows, 'chart_type' => 'stacked_bar', 'x_field' => 'bucket',
                                       'y_field' => 'value', 'series_field' => 'group' })
      expect(JSON.parse(result.last[:text])).to eq(budget_rows)
    end
  end
end
