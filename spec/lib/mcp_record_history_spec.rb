# frozen_string_literal: true

# record_history's version/diff logic, on hand-built snapshots: no database,
# no ontology (the field catalogue and fixed-list labels are stubbed).
RSpec.describe Mcp::Tools::RecordHistory do
  def triples_for(values)
    values.flat_map do |questionclass, vals|
      Array(vals).flat_map do |value|
        attr = RDF::URI("urn:test:attr/#{questionclass}/#{SecureRandom.uuid}")
        [RDF::Statement.new(attr, RDF.type, RDF::URI("#{CBGP_NS}#{questionclass}")),
         RDF::Statement.new(attr, RDF::URI(SIO_VALUE_PREDICATE), RDF::Literal(value.to_s))]
      end
    end
  end

  def version(values, from:, until_at: nil, reason: nil, graph: 'urn:test:history/1')
    { graph_uri: graph, triples: triples_for(values), generated_at: from, invalidated_at: until_at, reason: reason, detail: nil }
  end

  let(:fields) do
    { 'p_name' => { questionclass: 'p_name', label: 'Name', answers: '' },
      'p_kind' => { questionclass: 'p_kind', label: 'Kind', answers: 'https://example.org#kinds' } }
  end
  let(:ctx) do
    instance_double(Mcp::Records::Context).tap do |c|
      allow(c).to receive(:vocabulary_label) { |field, id| field && field[:questionclass] == 'p_kind' && id == 'k1' ? 'Kind One' : nil }
    end
  end

  describe '.fields_of' do
    it 'reads every stored field out of raw snapshot triples, repeated values together' do
      state = described_class.fields_of(triples_for('p_name' => 'Ana', 'tags' => %w[a b]))
      expect(state['p_name']).to eq(['Ana'])
      expect(state['tags']).to contain_exactly('a', 'b')
    end

    it 'still reads a field the ontology no longer has' do
      expect(described_class.fields_of(triples_for('removed_field' => 'x'))['removed_field']).to eq(['x'])
    end
  end

  describe '.build_versions' do
    def build(versions)
      states = versions.map { |v| described_class.fields_of(v[:triples]) }
      described_class.build_versions(ctx, instance_double(Mcp::Records::FormInfo, name: 'p'), versions, states)
    end

    before { allow(ctx).to receive(:fields).and_return(fields.values) }

    it 'lists the creation values for the first version and only the changes after' do
      out = build([version({ 'p_name' => 'Ana', 'p_kind' => 'k1' }, from: '2020-01-01T00:00:00Z', until_at: '2021-01-01T00:00:00Z'),
                   version({ 'p_name' => 'Ana', 'p_kind' => 'k2' }, from: '2021-01-01T00:00:00Z', graph: 'urn:test:context/1')])
      expect(out[0]).to include(version: 1, kind: 'created', valid_from: '2020-01-01T00:00:00Z', valid_until: '2021-01-01T00:00:00Z')
      expect(out[0][:values]).to eq('p_name' => 'Ana', 'p_kind' => 'k1')
      expect(out[1]).to include(version: 2, kind: 'changed', valid_from: '2021-01-01T00:00:00Z', valid_until: nil)
      expect(out[1][:changes]).to eq([{ field: 'p_kind', label: 'Kind', from: 'Kind One (k1)', to: 'k2' }])
    end

    it 'reports an added and a removed field as a change from or to nothing' do
      out = build([version({ 'p_name' => 'Ana' }, from: 'a'), version({ 'p_kind' => 'k1' }, from: 'b')])
      expect(out[1][:changes]).to contain_exactly(
        { field: 'p_name', label: 'Name', from: 'Ana', to: nil },
        { field: 'p_kind', label: 'Kind', from: nil, to: 'Kind One (k1)' }
      )
    end

    it 'does not call a reordering of repeated values a change' do
      out = build([version({ 'tags' => %w[a b] }, from: 'a'), version({ 'tags' => %w[b a] }, from: 'b')])
      expect(out[1][:changes]).to eq([])
    end

    it 'labels a field the ontology no longer has by its stored name' do
      out = build([version({ 'gone' => 'x' }, from: 'a'), version({ 'gone' => 'y' }, from: 'b')])
      expect(out[1][:changes]).to eq([{ field: 'gone', label: 'gone', from: 'x', to: 'y' }])
    end

    it 'ends a deleted record with a deleted entry carrying the reason' do
      out = build([version({ 'p_name' => 'Ana' }, from: '2020-01-01T00:00:00Z', until_at: '2022-05-05T00:00:00Z', reason: 'deleted')])
      expect(out.last).to eq(version: 2, kind: 'deleted', valid_from: '2022-05-05T00:00:00Z', reason: 'deleted')
    end

    it 'carries a version\'s reason when it has one' do
      out = build([version({ 'p_name' => 'Ana' }, from: 'a', until_at: 'b', reason: 'edited'), version({ 'p_name' => 'Bo' }, from: 'b')])
      expect(out[0][:reason]).to eq('edited')
    end
  end
end
