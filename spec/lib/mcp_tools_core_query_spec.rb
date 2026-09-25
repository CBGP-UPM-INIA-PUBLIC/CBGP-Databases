# frozen_string_literal: true

# SearchRecords, GetRecord, Aggregate, PublicationProjectHeuristicLink
# (lib/mcp_tools/core/) all call the same top-level query functions
# routes.rb's own handlers call (execute_search, fetch_datasets_raw_data,
# retrieve_dataset_graph_query - see lib/queries.rb). Those are bare
# top-level methods (private on Object), so - same reasoning as
# spec/routes_active_members_spec.rb - they're stubbed with `allow(<the
# calling class>).to receive(...)` rather than a network double, no live
# Virtuoso needed.
#
# Every .with(...) matcher below uses hash_including(...), never a literal
# kwargs hash - see feedback memory on this Gemfile.lock's rspec-mocks/Ruby
# combo: allow(x).to receive(:m).with(literal_kwargs_hash) silently
# mismatches even when the printed "expected"/"got" look identical.
RSpec.describe 'Core MCP query tools' do
  describe McpTools::Core::SearchRecords do
    it 'searches, fetches details, and serializes each result as compact JSON-LD with a real @id' do
      allow(described_class).to receive(:execute_search)
        .with(hash_including(dataset_type: 'member', search_params: { 'member_name' => 'maria' }))
        .and_return(['https://w3id.org/CBGP-App/member/context/123'])
      allow(described_class).to receive(:fetch_datasets_raw_data)
        .with(hash_including(graph_uris: ['https://w3id.org/CBGP-App/member/context/123'], database: 'member'))
        .and_return([{ dataset: 'https://w3id.org/CBGP-App/member/context/123', member_name: 'Maria' }])

      response = described_class.call({ 'form_type' => 'member', 'search_params' => { 'member_name' => 'maria' } })
      body = JSON.parse(response.first[:text])

      expect(body['total_matches']).to eq(1)
      expect(body['records'].first['@id']).to eq('https://w3id.org/CBGP-App/member/context/123')
      expect(body['records'].first['member_name']).to eq('Maria')
    end

    it 'caps returned results at the limit while still reporting the true total_matches' do
      graphs = (1..5).map { |i| "urn:g#{i}" }
      allow(described_class).to receive(:execute_search).and_return(graphs)
      # Generic stub (no .with): search_records.rb caps graph_uris to `limit`
      # BEFORE calling fetch_datasets_raw_data, so only 2 URIs are ever
      # actually passed through - returning a fixed 2-row result is enough
      # to pin "returned"/"records.size" without needing to echo the args.
      allow(described_class).to receive(:fetch_datasets_raw_data)
        .and_return([{ dataset: 'urn:g1' }, { dataset: 'urn:g2' }])

      response = described_class.call({ 'form_type' => 'member', 'limit' => 2 })
      body = JSON.parse(response.first[:text])

      expect(body['total_matches']).to eq(5)
      expect(body['returned']).to eq(2)
      expect(body['records'].size).to eq(2)
    end
  end

  describe McpTools::Core::GetRecord do
    it 'resolves primary_id to a graph, fetches it, and serializes it' do
      solutions = [{ g: RDF::URI('https://w3id.org/CBGP-App/member/context/123') }]
      allow(described_class).to receive(:retrieve_dataset_graph_query)
        .with(hash_including(primary_id: '0000-0001-2345-6789')).and_return(solutions)
      allow(described_class).to receive(:fetch_datasets_raw_data)
        .with(hash_including(graph_uris: ['https://w3id.org/CBGP-App/member/context/123'], database: 'member'))
        .and_return([{ dataset: 'https://w3id.org/CBGP-App/member/context/123', member_orcid: '0000-0001-2345-6789' }])

      response = described_class.call({ 'form_type' => 'member', 'primary_id' => '0000-0001-2345-6789' })
      body = JSON.parse(response.first[:text])

      expect(body['@id']).to eq('https://w3id.org/CBGP-App/member/context/123')
    end

    it 'raises a clear error when no record matches, rather than returning something empty/ambiguous' do
      allow(described_class).to receive(:retrieve_dataset_graph_query).and_return([])

      expect do
        described_class.call({ 'form_type' => 'member', 'primary_id' => 'nonexistent' })
      end.to raise_error(/No member record found/)
    end
  end

  describe McpTools::Core::Aggregate do
    it 'groups and counts records by a field' do
      allow(described_class).to receive(:execute_search).and_return(%w[g1 g2 g3])
      allow(described_class).to receive(:fetch_datasets_raw_data).and_return([
                                                                                 { dataset: 'g1', project_type: 'European' },
                                                                                 { dataset: 'g2', project_type: 'National' },
                                                                                 { dataset: 'g3', project_type: 'European' }
                                                                               ])

      response = described_class.call({ 'form_type' => 'project', 'group_by' => 'project_type' })
      body = JSON.parse(response.first[:text])

      expect(body).to eq({ 'European' => 2, 'National' => 1 })
    end

    it 'sums a metric field per group' do
      allow(described_class).to receive(:execute_search).and_return(%w[g1 g2])
      allow(described_class).to receive(:fetch_datasets_raw_data).and_return([
                                                                                 { dataset: 'g1', project_type: 'European', project_total_funding: '100' },
                                                                                 { dataset: 'g2', project_type: 'European', project_total_funding: '200' }
                                                                               ])

      response = described_class.call({
                                         'form_type' => 'project', 'group_by' => 'project_type',
                                         'metric' => 'project_total_funding', 'agg_op' => 'sum'
                                       })
      body = JSON.parse(response.first[:text])

      expect(body['European']).to eq(300.0)
    end
  end

  describe McpTools::Core::PublicationProjectHeuristicLink do
    it 'matches a publication whose author ORCID overlaps the project PI ORCID within the date window, and labels the result inferred' do
      allow(described_class).to receive(:retrieve_dataset_graph_query)
        .with(hash_including(primary_id: 'PROJ-1')).and_return([{ g: RDF::URI('urn:project-graph') }])
      allow(described_class).to receive(:fetch_datasets_raw_data)
        .with(hash_including(graph_uris: ['urn:project-graph'], database: 'project'))
        .and_return([{
                       dataset: 'urn:project-graph', project_pi_orcid: ['0000-0001-2345-6789'],
                       project_start_date: '2023-01-01', project_end_date: '2023-12-31'
                     }])
      allow(described_class).to receive(:execute_search).and_return(['urn:pub-graph'])
      allow(described_class).to receive(:fetch_datasets_raw_data)
        .with(hash_including(graph_uris: ['urn:pub-graph'], database: 'publication'))
        .and_return([{ dataset: 'urn:pub-graph', publication_authors: ['0000-0001-2345-6789'], publication_date: '2023-06-01' }])

      response = described_class.call({
                                         'project_form_type' => 'project', 'project_primary_id' => 'PROJ-1',
                                         'pi_orcid_fields' => ['project_pi_orcid'],
                                         'project_start_date_field' => 'project_start_date',
                                         'project_end_date_field' => 'project_end_date',
                                         'publication_author_orcid_field' => 'publication_authors'
                                       })
      body = JSON.parse(response.first[:text])

      expect(body['note']).to match(/INFERRED/)
      expect(body['matches'].first['publication']).to eq('urn:pub-graph')
      expect(body['matches'].first['matched_orcid']).to eq('0000-0001-2345-6789')
    end
  end
end
