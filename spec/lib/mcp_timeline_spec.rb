# frozen_string_literal: true

# The generic timeline widget (lib/mcp/widgets/timeline.rb) and the tool that
# exposes it. The widget takes rows of {label, start, end, lane} and knows
# nothing about what they mean.
RSpec.describe Mcp::Widgets::Timeline do
  let(:today) { Date.new(2026, 10, 8) }

  def render(rows, **opts)
    described_class.render(rows: rows, today: today, **opts)
  end

  it 'draws bars, points and an ongoing bar, grouped into lanes in order of first appearance' do
    out = render([
                   { 'lane' => 'Funding', 'label' => 'ALFA', 'start' => '2024-01-01', 'end' => '2025-06-30' },
                   { 'lane' => 'Papers', 'label' => 'Paper', 'start' => '2025-03-12' },
                   { 'lane' => 'Funding', 'label' => 'BETA', 'start' => '2025-07-01', 'ongoing' => true }
                 ], title: 'Ana')
    expect(out[:rows]).to eq(3)
    expect(out[:lanes]).to eq(%w[Funding Papers])
    expect(out[:html]).to include('<h1>Ana</h1>', '<polygon', 'ongoing', 'class="today"')
    expect(out[:html].scan('<rect x=').size).to eq(2) # two bars (ALFA, BETA)
  end

  it 'runs an ongoing bar to today, so the range ends at today plus padding' do
    out = render([{ 'label' => 'x', 'start' => '2026-01-01', 'ongoing' => true }])
    expect(Date.iso8601(out[:to])).to be >= today
    expect(Date.iso8601(out[:from])).to be <= Date.new(2026, 1, 1)
  end

  it 'does not draw an ongoing row that has not started yet as running backwards' do
    out = render([{ 'label' => 'later', 'start' => '2026-12-01', 'ongoing' => true }])
    expect(Date.iso8601(out[:to])).to be >= Date.new(2026, 12, 1)
    expect(out[:html]).to include('<polygon').or include('<rect x=')
  end

  it 'does not extend a finished row to today' do
    out = render([{ 'label' => 'x', 'start' => '2020-01-01', 'end' => '2020-12-31' }])
    expect(Date.iso8601(out[:to])).to be < Date.new(2021, 3, 1)
    expect(out[:html]).not_to include('class="today"')
  end

  it 'accepts a full timestamp and the word today as dates' do
    out = render([{ 'label' => 'x', 'start' => '2025-09-29T19:42:11.736451Z', 'end' => 'today' }])
    expect(out[:from]).to start_with('2025-09')
  end

  it 'escapes text from the rows so a label cannot inject markup' do
    out = render([{ 'label' => '<script>alert(1)</script>', 'start' => '2025-01-01', 'detail' => '"><img>' }])
    expect(out[:html]).not_to include('<script>')
    expect(out[:html]).to include('&lt;script&gt;')
    expect(out[:html]).not_to include('"><img>')
  end

  it 'gives a lone point a usable range' do
    out = render([{ 'label' => 'x', 'start' => '2025-01-01' }])
    expect(Date.iso8601(out[:from])).to be < Date.iso8601(out[:to])
  end

  it 'puts rows with no lane in one default lane' do
    expect(render([{ 'label' => 'x', 'start' => '2025-01-01' }])[:lanes]).to eq(['Events'])
  end

  describe 'rejects bad input with a message that says what to fix' do
    it('no rows') { expect { render([]) }.to raise_error(Mcp::ToolError, /non-empty list/) }
    it('not a list') { expect { render('x') }.to raise_error(Mcp::ToolError, /non-empty list/) }
    it('missing label') { expect { render([{ 'start' => '2025-01-01' }]) }.to raise_error(Mcp::ToolError, /Row 1 has no label/) }
    it('missing start') { expect { render([{ 'label' => 'x' }]) }.to raise_error(Mcp::ToolError, /Row 1 \(x\)|row 1 start/) }
    it('invalid date') { expect { render([{ 'label' => 'x', 'start' => '2025-13-40' }]) }.to raise_error(Mcp::ToolError, /not a date/) }
    it('end before start') { expect { render([{ 'label' => 'x', 'start' => '2025-05-01', 'end' => '2025-01-01' }]) }.to raise_error(Mcp::ToolError, /end is before start/) }
    it('too many rows') do
      rows = Array.new(151) { |i| { 'label' => i.to_s, 'start' => '2025-01-01' } }
      expect { render(rows) }.to raise_error(Mcp::ToolError, /At most 150/)
    end
  end
end

RSpec.describe Mcp::Tools::RenderTimeline do
  it 'returns a summary text block and the widget as an HTML resource' do
    content = described_class.invoke('rows' => [{ 'label' => 'x', 'start' => '2025-01-01', 'end' => '2025-06-01' }], 'title' => 'T')
    expect(content.map { |b| b[:type] }).to eq(%w[text resource])
    expect(JSON.parse(content.first[:text])).to include('drawn' => 1)
    expect(content.last[:resource]).to include(mimeType: 'text/html')
    expect(content.last[:resource][:uri]).to start_with('ui://timeline/')
    expect(content.last[:resource][:text]).to start_with('<!doctype html>')
  end
end

RSpec.describe Mcp::Widgets::Timeline, 'label placement' do
  let(:today) { Date.new(2026, 10, 8) }

  def labels(rows)
    described_class.render(rows: rows, today: today)[:html].scan(%r{<text class="(lbl[^"]*)" x="([\d.]+)"[^>]*text-anchor="(\w+)">([^<]*)</text>})
  end

  it 'never starts a label left of the lane-name gutter' do
    long = 'A very long label that cannot fit anywhere near the start of the bar at all' * 2
    rows = [{ 'label' => long, 'start' => '2020-01-01', 'end' => '2026-06-01' }, { 'label' => 'x', 'start' => '2026-06-02' }]
    labels(rows).each do |_cls, x, anchor, _text|
      expect(anchor == 'end' ? x.to_f - 1 : x.to_f).to be >= described_class::LEFT
    end
  end

  it 'puts a label that fits on neither side inside a long bar, and cuts it to the bar' do
    rows = [{ 'label' => 'Alvarez Alfageme, Olga - UI-TEST project TWO (delete me)', 'start' => '2026-01-01', 'ongoing' => true },
            { 'label' => 'filler', 'start' => '2026-01-01', 'end' => '2026-02-01' }]
    cls, _x, _anchor, text = labels(rows).first
    expect(cls).to eq('lbl inbar')
    expect(text.length).to be <= 48
  end

  it 'leaves a short label beside its mark at full length' do
    rows = [{ 'label' => 'ALFA', 'start' => '2024-01-01', 'end' => '2024-03-01' }, { 'label' => 'x', 'start' => '2026-06-02' }]
    cls, _x, anchor, text = labels(rows).first
    expect([cls, anchor, text]).to eq(['lbl', 'start', 'ALFA'])
  end
end

RSpec.describe Mcp::Widgets::Timeline, 'in Spanish' do
  let(:today) { Date.new(2026, 10, 8) }
  let(:rows) { [{ 'label' => 'A', 'start' => '2026-01-01', 'ongoing' => true }, { 'label' => 'B', 'start' => '2026-03-01', 'end' => '2026-08-01' }] }

  it 'writes month names, the ongoing word and the page language in Spanish' do
    html = described_class.render(rows: rows, today: today, language: 'es')[:html]
    expect(html).to include('<html lang="es">', 'en curso')
    expect(html).to match(/>(ene|feb|mar|abr|may|jun|jul|ago|sep|oct|nov|dic)</)
    expect(html).not_to include('>Jan<', '>Apr<', 'ongoing')
  end

  it 'stays English by default and falls back to it for an unknown language' do
    expect(described_class.render(rows: rows, today: today)[:html]).to include('<html lang="en">', 'ongoing')
    expect(described_class.render(rows: rows, today: today, language: 'fr')[:html]).to include('<html lang="en">')
  end

  it 'accepts hoy as a date' do
    out = described_class.render(rows: [{ 'label' => 'x', 'start' => '2026-01-01', 'end' => 'hoy' }], today: today)
    expect(Date.iso8601(out[:to])).to be >= today
  end

  it 'gets its language from the tool call' do
    content = Mcp::Tools::RenderTimeline.invoke('rows' => rows, 'title' => 'T', 'language' => 'es')
    expect(content.last[:resource][:text]).to include('<html lang="es">')
  end
end
