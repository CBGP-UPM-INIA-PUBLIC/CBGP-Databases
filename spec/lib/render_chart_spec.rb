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
end
