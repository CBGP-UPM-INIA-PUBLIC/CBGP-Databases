# frozen_string_literal: true

# Covers the dcterms:type provenance stamp added 2026-07-28: every record,
# on every form, automatically gets dcterms:type <form-class-uri> written
# onto its graph at save time (write_dataset_to_db_query, lib/queries.rb) -
# alongside the dcterms:created/dcterms:modified triples already covered by
# spec/lib/history_capture_spec.rb, in the exact same spot (the default
# graph, subject = the graph URI).
#
# This replaced project_category, a hand-declared hidden discriminator field
# that only existed to answer "which of these two forms wrote this record" -
# see spec/lib/form_defaults_spec.rb for that history. The structural
# version generalizes to every form (not just ones an ontology editor
# thought to wire up) and can't be forgotten, because there's nothing to
# configure: the value comes directly from the +form:+ parameter already
# threaded through the save path, not from anything declared in the
# ontology.
RSpec.describe 'dcterms:type provenance stamp' do
  let(:dataset) do
    ds = CBGP::Dataset.new(type: 'project')
    ds.primary_id = 'abc-123'
    ds.title = 'A Project'
    ds
  end

  describe '#write_dataset_to_db_query' do
    it 'stamps dcterms:type with the explicitly-given form, not the dbname' do
      query = write_dataset_to_db_query(dataset: dataset, oldid: nil, form: 'personnel_project')
      expect(query).to include('dcterms:type cbgp:personnel_project')
    end

    it 'stamps a different form differently for the exact same dataset/dbname' do
      research_query = write_dataset_to_db_query(dataset: dataset, oldid: nil, form: 'project')
      personnel_query = write_dataset_to_db_query(dataset: dataset, oldid: nil, form: 'personnel_project')

      expect(research_query).to include('dcterms:type cbgp:project')
      expect(personnel_query).to include('dcterms:type cbgp:personnel_project')
    end

    it 'falls back to the dataset\'s dbname when no form: is given, same fallback as its siblings' do
      query = write_dataset_to_db_query(dataset: dataset, oldid: nil)
      expect(query).to include('dcterms:type cbgp:project') # dataset.form_type == "project" (the dbname here)
    end

    it 'writes dcterms:type in the same default-graph provenance block as dcterms:created/dcterms:modified' do
      query = write_dataset_to_db_query(dataset: dataset, oldid: nil, form: 'personnel_project')

      # All three provenance triples share one subject (datasetgraph:<id>)
      # and must sit OUTSIDE the named GRAPH {} block - same reasoning as
      # dcterms:created/modified (see history_capture_spec.rb): queryable
      # without knowing the graph URI, and untouched by a later
      # snapshot/drop of the named graph itself.
      # split('}', 2) — everything after the FIRST closing brace, i.e. after
      # the named GRAPH {...} block ends. The query has exactly two closing
      # braces (one for GRAPH, one for the outer INSERT DATA); splitting on
      # ALL of them would leave nothing but a trailing newline in .last.
      provenance_block = query.split('}', 2).last
      expect(provenance_block).to include('dcterms:modified')
      expect(provenance_block).to include('dcterms:created')
      expect(provenance_block).to include('dcterms:type cbgp:personnel_project')
    end
  end

  describe 'CBGP::Dataset.load_from_params_and_write' do
    it 'passes the true form (not the shared dbname) through to the write, for a Personnel submission' do
      allow(CBGP::Dataset).to receive(:write_dataset_to_db)
      params = { 'database' => 'project', 'primary_id' => '', 'project_annual_income' => '1000.00' }

      CBGP::Dataset.load_from_params_and_write(params: params, form: 'personnel_project')

      expect(CBGP::Dataset).to have_received(:write_dataset_to_db).with(
        hash_including(form: 'personnel_project')
      )
    end
  end
end
