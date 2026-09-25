# frozen_string_literal: true

# McpTools::Shared::ComputeStatistics (lib/mcp_tools/shared/compute_statistics.rb) -
# pure arithmetic over rows another tool already returned, so a
# budget-constrained model doesn't have to do the math itself. Every call
# goes through .call(arguments) and back out as a JSON text content block,
# matching how the MCP dispatcher actually invokes it.
RSpec.describe McpTools::Shared::ComputeStatistics do
  def call(**arguments)
    result = described_class.call(arguments.transform_keys(&:to_s))
    JSON.parse(result.first[:text])
  end

  describe 'correlation' do
    it 'computes a near-1.0 r for near-linearly related fields' do
      rows = [
        { 'x' => '1', 'y' => '2' },
        { 'x' => '2', 'y' => '4.1' },
        { 'x' => '3', 'y' => '5.9' },
        { 'x' => '4', 'y' => '8' }
      ]
      result = call(rows: rows, operation: 'correlation', x_field: 'x', y_field: 'y')
      expect(result['r']).to be > 0.99
      expect(result['n']).to eq(4)
    end

    it 'skips rows missing either field rather than raising' do
      rows = [{ 'x' => '1', 'y' => '2' }, { 'x' => '2' }, { 'x' => '3', 'y' => '6' }, { 'x' => '4', 'y' => '8' }]
      result = call(rows: rows, operation: 'correlation', x_field: 'x', y_field: 'y')
      expect(result['n']).to eq(3)
    end

    it 'returns nil rather than a misleading number when there are fewer than 3 usable rows' do
      rows = [{ 'x' => '1', 'y' => '2' }]
      expect(call(rows: rows, operation: 'correlation', x_field: 'x', y_field: 'y')).to be_nil
    end
  end

  describe 'mean/sum/count' do
    let(:rows) { [{ 'amount' => '10' }, { 'amount' => '20' }, { 'amount' => 'not-a-number' }] }

    it 'computes the mean over only the numeric-parseable rows' do
      expect(call(rows: rows, operation: 'mean', field: 'amount')).to eq(15.0)
    end

    it 'computes the sum over only the numeric-parseable rows' do
      expect(call(rows: rows, operation: 'sum', field: 'amount')).to eq(30.0)
    end

    it 'counts every row regardless of field content' do
      expect(call(rows: rows, operation: 'count')).to eq(3)
    end
  end

  describe 'proportion' do
    it 'computes the fraction of rows matching a value' do
      rows = [{ 'status' => 'Active' }, { 'status' => 'Active' }, { 'status' => 'Inactive' }, { 'status' => 'Active' }]
      expect(call(rows: rows, operation: 'proportion', field: 'status', value: 'Active')).to eq(0.75)
    end
  end

  describe 'group_by' do
    it 'splits the result into one entry per distinct group value' do
      rows = [
        { 'type' => 'European', 'amount' => '100' },
        { 'type' => 'National', 'amount' => '50' },
        { 'type' => 'European', 'amount' => '200' }
      ]
      result = call(rows: rows, operation: 'sum', field: 'amount', group_by: 'type')
      expect(result).to eq({ 'European' => 300.0, 'National' => 50.0 })
    end
  end

  it 'raises on an unrecognized operation rather than silently returning something' do
    expect { described_class.call({ 'rows' => [], 'operation' => 'nonsense' }) }.to raise_error(ArgumentError)
  end
end
