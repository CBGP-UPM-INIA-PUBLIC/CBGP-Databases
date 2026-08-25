# frozen_string_literal: true

# Covers the SCD Type 2 history-recording mechanism added 2026-07-07:
# delete_dataset_query snapshots a graph's prior state into the separate
# HISTORY_DATABASE repository before dropping it from the current one, and
# write_dataset_to_db_query threads a change summary + preserved
# dcterms:created through it. See lib/queries.rb and the plan at
# .claude/plans/enumerated-zooming-sedgewick.md for the full design.
RSpec.describe 'SCD Type 2 history capture' do
  let(:old_graph_uri) { "#{BASE_URI}project/context/abc-123" }

  describe '#delete_dataset_query' do
    let(:prov_solution) do
      RDF::Query::Solution.new(
        created: RDF::Literal.new('2020-01-01T00:00:00Z', datatype: RDF::XSD.dateTime),
        modified: RDF::Literal.new('2024-06-15T10:00:00Z', datatype: RDF::XSD.dateTime)
      )
    end
    let(:constructed_triples) do
      RDF::Graph.new { |g| g << [RDF::URI('urn:x'), RDF::URI('urn:y'), RDF::Literal('z')] }
    end

    before do
      allow(DATABASE).to receive(:query)
        .with(a_string_matching(/SELECT \?created \?modified/))
        .and_return([prov_solution])
      allow(DATABASE).to receive(:query)
        .with(a_string_matching(/CONSTRUCT/))
        .and_return(constructed_triples)
      allow(HISTORY_DATABASE_UPDATE).to receive(:insert_data)
      allow(HISTORY_DATABASE_UPDATE).to receive(:update)
      allow(DATABASE_UPDATE).to receive(:update)
    end

    it 'defaults reason to "deleted" and detail to "Record deleted"' do
      delete_dataset_query(oldid: old_graph_uri)
      expect(HISTORY_DATABASE_UPDATE).to have_received(:update).with(
        a_string_matching(/local:history-reason\s+"deleted"/)
          .and(a_string_matching(/local:history-detail\s+"Record deleted"/))
      )
    end

    it 'accepts an explicit reason and detail (the edit path)' do
      delete_dataset_query(oldid: old_graph_uri, reason: 'superseded', detail: 'Title: Old → New')
      expect(HISTORY_DATABASE_UPDATE).to have_received(:update).with(
        a_string_matching(/local:history-reason\s+"superseded"/)
          .and(a_string_matching(/local:history-detail\s+"Title: Old → New"/))
      )
    end

    it 'stamps prov:generatedAtTime from the prior dcterms:modified and prov:invalidatedAtTime as now' do
      delete_dataset_query(oldid: old_graph_uri)
      expect(HISTORY_DATABASE_UPDATE).to have_received(:update).with(
        a_string_matching(/prov:generatedAtTime\s+"2024-06-15T10:00:00Z"/)
          .and(a_string_matching(/prov:invalidatedAtTime\s+"\d{4}-\d{2}-\d{2}T/))
      )
    end

    it 'copies the constructed triples into a new /history/<primary_id>/<uuid> graph, not /context/' do
      delete_dataset_query(oldid: old_graph_uri)
      expected_graph_pattern = %r{\A#{Regexp.escape(BASE_URI)}project/history/abc-123/[0-9a-f-]{36}\z}
      expect(HISTORY_DATABASE_UPDATE).to have_received(:insert_data).with(
        constructed_triples,
        hash_including(graph: a_string_matching(expected_graph_pattern))
      )
    end

    it 'still drops the live graph from the current repository, unchanged from before' do
      delete_dataset_query(oldid: old_graph_uri)
      expect(DATABASE_UPDATE).to have_received(:update)
        .with(a_string_matching(/DROP GRAPH <#{Regexp.escape(old_graph_uri)}>/))
    end

    it 'returns the prior dcterms:created and the new history graph URI' do
      result = delete_dataset_query(oldid: old_graph_uri)
      expect(result[:created]).to eq('2020-01-01T00:00:00Z')
      expect(result[:history_graph]).to match(%r{/project/history/abc-123/})
    end
  end

  describe '#summarize_field_changes' do
    let(:string_field) do
      { method: :title, questionclass: 'project_title', label: 'Title', class: 'string', answers: "#{CBGP_KB}#FREE" }
    end
    let(:currency_field) do
      # personnel_project_total_funding: 'project' itself is no longer a
      # valid form type (Sara's 2026-08 restructuring split it into
      # per-funding-type forms); personnel_project is used here as a real
      # stand-in form with a currency field.
      { method: :total_funding, questionclass: 'personnel_project_total_funding', label: 'Total funding', class: 'currency',
        answers: "#{CBGP_KB}#NUM" }
    end
    # A real Dataset, not a double: its field getters are per-instance
    # singleton methods (defined in #initialize), not real methods on the
    # class, so RSpec's verifying doubles can't confirm they exist.
    let(:new_dataset) do
      ds = CBGP::Dataset.new(type: 'personnel_project')
      ds.title = 'New Title'
      ds.total_funding = '20000.00'
      ds
    end

    it 'omits fields whose value did not change' do
      summary = summarize_field_changes(
        fields: [string_field],
        old_values: { project_title: 'New Title' },
        new_dataset: new_dataset
      )
      expect(summary).to eq('')
    end

    it 'reports changed fields as "label: old → new", formatted through resolve_display_value' do
      summary = summarize_field_changes(
        fields: [string_field, currency_field],
        old_values: { project_title: 'Old Title', personnel_project_total_funding: '15000.00' },
        new_dataset: new_dataset
      )
      expect(summary).to eq('Title: Old Title → New Title; Total funding: 15,000.00 → 20,000.00')
    end

    it 'renders a previously-blank field as "(none)" on the old side' do
      summary = summarize_field_changes(
        fields: [string_field],
        old_values: {},
        new_dataset: new_dataset
      )
      expect(summary).to eq('Title: (none) → New Title')
    end
  end

  describe 'write_dataset_to_db_query (edit path wiring)' do
    let(:dataset) do
      ds = CBGP::Dataset.new(type: 'personnel_project')
      ds.primary_id = 'abc-123'
      ds.title = 'New Title'
      ds
    end

    it 'passes reason/detail through to delete_dataset_query and preserves dcterms:created' do
      allow(self).to receive(:fetch_datasets_raw_data).and_return([{ project_title: 'Old Title' }])
      allow(self).to receive(:delete_dataset_query)
        .and_return(created: '2020-01-01T00:00:00Z', history_graph: 'irrelevant')

      query = write_dataset_to_db_query(dataset: dataset, oldid: 'abc-123')

      expect(self).to have_received(:delete_dataset_query).with(
        oldid: "#{BASE_URI}personnel_project/context/abc-123",
        reason: 'superseded',
        detail: 'Title of the project: Old Title → New Title'
      )
      expect(query).to include('dcterms:created "2020-01-01T00:00:00Z"')
    end

    it 'writes a fresh dcterms:created for a brand-new record (no oldid)' do
      query = write_dataset_to_db_query(dataset: dataset, oldid: nil)
      expect(query).to match(/dcterms:created "\d{4}-\d{2}-\d{2}T/)
    end
  end
end
