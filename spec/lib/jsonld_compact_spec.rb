# frozen_string_literal: true

# Compact JSON-LD serialization for core-DB records (lib/jsonld_compact.rb),
# built directly on fetch_datasets_raw_data's existing output shape. Pins
# the two things that actually matter for the MCP servers to interoperate:
# @id carries the real graph URI (so a search_records result can be fed
# straight into a History-server tool argument), and the @context matches
# what history_queries.rb's own JSON-LD dumps already use.
RSpec.describe JsonldCompact do
  describe '.serialize_record' do
    let(:raw_record) do
      {
        dataset: 'https://w3id.org/CBGP-App/member/context/123',
        member_name: 'Elena',
        member_surnames: 'Garcia',
        publication_authors: %w[Elena Mark]
      }
    end

    it 'uses the graph URI as @id' do
      result = described_class.serialize_record(form_type: 'member', raw_record: raw_record)
      expect(result['@id']).to eq('https://w3id.org/CBGP-App/member/context/123')
    end

    it 'uses "cbgp:<form_type>" as @type' do
      result = described_class.serialize_record(form_type: 'member', raw_record: raw_record)
      expect(result['@type']).to eq('cbgp:member')
    end

    it 'flattens every other field to a plain string-keyed value, preserving arrays for Multiple fields' do
      result = described_class.serialize_record(form_type: 'member', raw_record: raw_record)
      expect(result['member_name']).to eq('Elena')
      expect(result['publication_authors']).to eq(%w[Elena Mark])
    end

    it 'does not leak the internal :dataset key into the output' do
      result = described_class.serialize_record(form_type: 'member', raw_record: raw_record)
      expect(result.key?(:dataset)).to be(false)
      expect(result.key?('dataset')).to be(false)
    end

    it 'includes a @context that matches the prefixes history_queries.rb dumps use' do
      result = described_class.serialize_record(form_type: 'member', raw_record: raw_record)
      expect(result['@context']['cbgp']).to eq(TIME_MACHINE_PREFIXES[:cbgp])
      expect(result['@context']['local']).to eq(TIME_MACHINE_PREFIXES[:local])
    end

    it 'does not mutate the caller\'s raw_record hash' do
      original = raw_record.dup
      described_class.serialize_record(form_type: 'member', raw_record: raw_record)
      expect(raw_record).to eq(original)
    end
  end

  describe '.serialize_records' do
    it 'serializes each record independently' do
      raw = [
        { dataset: 'urn:a', member_name: 'A' },
        { dataset: 'urn:b', member_name: 'B' }
      ]
      results = described_class.serialize_records(form_type: 'member', raw_records: raw)
      expect(results.map { |r| r['@id'] }).to eq(%w[urn:a urn:b])
    end
  end
end
