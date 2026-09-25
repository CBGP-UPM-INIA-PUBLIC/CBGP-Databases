# frozen_string_literal: true

# History MCP tools (lib/mcp_tools/history/) - all call the same top-level
# history_queries.rb functions the human-facing History API routes call
# (find_primary_id, full_timeline, filter_snapshots_during, ...). Same
# stubbing approach as spec/lib/mcp_tools_core_query_spec.rb: `allow(<tool
# class>).to receive(...)`, since these are bare top-level (Object-private)
# methods and self inside a tool's self.call is the tool class itself.
# Every .with(...) uses hash_including, never a literal kwargs hash - see
# feedback memory on this Gemfile.lock's rspec-mocks quirk.
RSpec.describe 'History MCP tools' do
  def field_triples(questionclass:, value:)
    attr = RDF::URI("urn:test:attr/#{questionclass}/#{SecureRandom.uuid}")
    [
      RDF::Statement.new(attr, RDF.type, RDF::URI("#{CBGP_NS}#{questionclass}")),
      RDF::Statement.new(attr, RDF::URI(SIO_VALUE_PREDICATE), RDF::Literal(value.to_s))
    ]
  end

  describe McpTools::History::RecordHistory do
    it 'returns each version with its fields and a diff from the previous version' do
      allow(described_class).to receive(:find_primary_id)
        .with(hash_including(form_type: 'member', questionclass: 'member_orcid', value: '0000-0001'))
        .and_return('m1')

      v1 = { graph_uri: 'g1', generated_at: '2023-01-01T00:00:00Z', invalidated_at: '2024-01-01T00:00:00Z',
             reason: 'superseded', detail: nil, triples: field_triples(questionclass: 'member_status', value: 'Active') }
      v2 = { graph_uri: 'g2', generated_at: '2024-01-01T00:00:00Z', invalidated_at: nil,
             reason: nil, detail: nil, triples: field_triples(questionclass: 'member_status', value: 'Inactive') }
      allow(described_class).to receive(:full_timeline)
        .with(hash_including(form_type: 'member', primary_id: 'm1')).and_return([v1, v2])

      response = described_class.call({ 'form_type' => 'member', 'questionclass' => 'member_orcid', 'value' => '0000-0001' })
      body = JSON.parse(response.first[:text])

      expect(body['primary_id']).to eq('m1')
      expect(body['timeline'].size).to eq(2)
      expect(body['timeline'][0]['changed']).to eq([{ 'field' => 'member_status', 'to' => ['Active'] }])
      expect(body['timeline'][1]['changed']).to eq([{ 'field' => 'member_status', 'from' => ['Active'], 'to' => ['Inactive'] }])
    end

    it 'raises a clear error when the identifier resolves to nothing' do
      allow(described_class).to receive(:find_primary_id).and_return(nil)
      expect do
        described_class.call({ 'form_type' => 'member', 'questionclass' => 'member_orcid', 'value' => 'nonexistent' })
      end.to raise_error(/No member record found/)
    end
  end

  describe McpTools::History::RecordTimeline do
    it 'labels each span with summary_field\'s value when given' do
      allow(described_class).to receive(:find_primary_id).and_return('m1')
      v1 = { graph_uri: 'g1', generated_at: '2018-01-01T00:00:00Z', invalidated_at: '2021-06-30T00:00:00Z',
             triples: field_triples(questionclass: 'member_category', value: 'Predoctoral') }
      v2 = { graph_uri: 'g2', generated_at: '2021-07-01T00:00:00Z', invalidated_at: nil,
             triples: field_triples(questionclass: 'member_category', value: 'Postdoctoral') }
      allow(described_class).to receive(:full_timeline).and_return([v1, v2])

      rows = JSON.parse(described_class.call({
                                                 'form_type' => 'member', 'questionclass' => 'member_orcid', 'value' => 'x',
                                                 'summary_field' => 'member_category'
                                               }).first[:text])

      expect(rows).to eq([
                           { 'label' => 'Predoctoral', 'start' => '2018-01-01T00:00:00Z', 'end' => '2021-06-30T00:00:00Z' },
                           { 'label' => 'Postdoctoral', 'start' => '2021-07-01T00:00:00Z' }
                         ])
    end

    it 'falls back to "Version N" labels when summary_field is omitted' do
      allow(described_class).to receive(:find_primary_id).and_return('m1')
      allow(described_class).to receive(:full_timeline)
        .and_return([{ graph_uri: 'g1', generated_at: '2020-01-01T00:00:00Z', invalidated_at: nil, triples: [] }])

      rows = JSON.parse(described_class.call({ 'form_type' => 'member', 'questionclass' => 'q', 'value' => 'v' }).first[:text])
      expect(rows.first['label']).to eq('Version 1')
    end
  end

  describe McpTools::History::TemporalSearch do
    it 'returns matching records flattened with @id and primary_id' do
      snap = { primary_id: 'p1', graph_uri: 'g1', is_current: true,
               triples: field_triples(questionclass: 'project_type', value: 'European') }
      allow(described_class).to receive(:filter_snapshots_during)
        .with(hash_including(form_type: 'project', facets: { 'project_type' => 'European' }))
        .and_return([snap])

      body = JSON.parse(described_class.call({ 'form_type' => 'project', 'facets' => { 'project_type' => 'European' } }).first[:text])

      expect(body['total_matches']).to eq(1)
      expect(body['records'].first['@id']).to eq('g1')
      expect(body['records'].first['primary_id']).to eq('p1')
      expect(body['records'].first['project_type']).to eq(['European'])
    end
  end

  describe McpTools::History::AggregateOverTime do
    it 'buckets by year and sums a metric per group' do
      # snapshot_field_values/sum_numeric_field are NOT mocked here - they're
      # pure functions over triples, no DB call, so they run for real against
      # the field_triples built below. Only filter_snapshots_during/
      # bucket_by_date (which would hit Virtuoso) are stubbed.
      european_2023 = { triples: field_triples(questionclass: 'project_type', value: 'European') +
                                  field_triples(questionclass: 'project_total_funding', value: '100000') }
      national_2023 = { triples: field_triples(questionclass: 'project_type', value: 'National') +
                                  field_triples(questionclass: 'project_total_funding', value: '40000') }
      european_2024 = { triples: field_triples(questionclass: 'project_type', value: 'European') +
                                  field_triples(questionclass: 'project_total_funding', value: '200000') }

      allow(described_class).to receive(:filter_snapshots_during)
        .and_return([european_2023, national_2023, european_2024])
      allow(described_class).to receive(:bucket_by_date)
        .and_return({ '2023' => [european_2023, national_2023], '2024' => [european_2024] })

      rows = JSON.parse(described_class.call({
                                                 'form_type' => 'project', 'date_field' => 'project_start_date',
                                                 'group_by' => 'project_type', 'metric' => 'project_total_funding', 'agg_op' => 'sum'
                                               }).first[:text])

      expect(rows).to contain_exactly(
        { 'bucket' => '2023', 'group' => 'European', 'value' => 100_000.0 },
        { 'bucket' => '2023', 'group' => 'National', 'value' => 40_000.0 },
        { 'bucket' => '2024', 'group' => 'European', 'value' => 200_000.0 }
      )
    end

    it 'counts per bucket with no group_by' do
      snaps2023 = [{ triples: [] }, { triples: [] }]
      allow(described_class).to receive(:filter_snapshots_during).and_return(snaps2023)
      allow(described_class).to receive(:bucket_by_date).and_return({ '2023' => snaps2023 })

      rows = JSON.parse(described_class.call({ 'form_type' => 'project', 'date_field' => 'project_start_date' }).first[:text])
      expect(rows).to eq([{ 'bucket' => '2023', 'value' => 2 }])
    end

    it 'raises on an unknown agg_op' do
      allow(described_class).to receive(:filter_snapshots_during).and_return([])
      allow(described_class).to receive(:bucket_by_date).and_return({ '2023' => [] })
      expect do
        described_class.call({ 'form_type' => 'project', 'date_field' => 'x', 'agg_op' => 'median' })
      end.to raise_error(ArgumentError)
    end
  end

  describe McpTools::History::PointInTimeSnapshot do
    it 'returns each as-of record with @id, primary_id, and its fields' do
      allow(described_class).to receive(:snapshot_as_of)
        .with(hash_including(form_type: 'member', as_of_date: '2023-06-01'))
        .and_return([{ primary_id: 'm1', graph_uri: 'g1', generated_at: '2023-01-01T00:00:00Z',
                        fields: { 'member_status' => ['Active'] } }])

      body = JSON.parse(described_class.call({ 'form_type' => 'member', 'as_of_date' => '2023-06-01' }).first[:text])

      expect(body['total_records']).to eq(1)
      expect(body['records'].first['@id']).to eq('g1')
      expect(body['records'].first['member_status']).to eq(['Active'])
    end
  end

  describe McpTools::History::InstituteTimeline do
    it 'builds one row per record spanning its whole lifetime' do
      snap = { primary_id: 'proj1', graph_uri: 'g1', is_current: true, triples: [] }
      allow(described_class).to receive(:filter_snapshots_during).and_return([snap])
      allow(described_class).to receive(:full_timeline)
        .with(hash_including(form_type: 'project', primary_id: 'proj1'))
        .and_return([
                      { graph_uri: 'g0', generated_at: '2020-01-01T00:00:00Z', invalidated_at: nil,
                        triples: field_triples(questionclass: 'project_type', value: 'European') }
                    ])

      rows = JSON.parse(described_class.call({ 'form_type' => 'project', 'summary_field' => 'project_type' }).first[:text])

      expect(rows).to eq([{ 'label' => 'European', 'start' => '2020-01-01T00:00:00Z', 'primary_id' => 'proj1' }])
    end

    it 'falls back to primary_id as the label when summary_field is omitted or blank for that record' do
      snap = { primary_id: 'proj1', graph_uri: 'g1', is_current: true, triples: [] }
      allow(described_class).to receive(:filter_snapshots_during).and_return([snap])
      allow(described_class).to receive(:full_timeline)
        .and_return([{ graph_uri: 'g0', generated_at: '2020-01-01T00:00:00Z', invalidated_at: nil, triples: [] }])

      rows = JSON.parse(described_class.call({ 'form_type' => 'project' }).first[:text])
      expect(rows.first['label']).to eq('proj1')
    end
  end
end
