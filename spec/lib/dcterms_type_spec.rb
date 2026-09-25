# frozen_string_literal: true

# Covers the dcterms:type provenance stamp added 2026-07-28: every record,
# on every form, automatically gets dcterms:type <form-class-uri> written
# onto its graph at save time (write_dataset_to_db_query, lib/queries.rb) -
# alongside the dcterms:created/dcterms:modified triples already covered by
# spec/lib/history_capture_spec.rb, in the exact same spot (inside the
# record's own named graph, subject = the graph URI - moved there from the
# default graph 2026-08-26, since Virtuoso's INSERT DATA rejects a bare
# triple with no GRAPH {} wrapper and no default-graph preamble, which
# SPARQL 1.1 doesn't provide a way to supply for INSERT DATA specifically;
# GraphDB tolerated the old placement, Virtuoso doesn't).
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
    # 'project' itself is no longer a valid form type - Sara's 2026-08
    # restructuring split it into per-funding-type forms; personnel_project
    # is used here as a stand-in real form, but the dcterms:type stamp under
    # test is driven entirely by the `form:` string passed to
    # write_dataset_to_db_query, not by this dataset's own type.
    ds = CBGP::Dataset.new(type: 'personnel_project')
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
      expect(query).to include('dcterms:type cbgp:personnel_project') # dataset.form_type == "personnel_project"
    end

    it 'writes dcterms:type inside the same named GRAPH block as dcterms:created/dcterms:modified' do
      query = write_dataset_to_db_query(dataset: dataset, oldid: nil, form: 'personnel_project')

      # All three provenance triples share one subject (datasetgraph:<id>)
      # and must sit INSIDE the named GRAPH {} block, alongside the field
      # data - see this file's header comment for why (Virtuoso rejects a
      # bare default-graph triple in INSERT DATA). The query has exactly one
      # GRAPH {...} block and everything belongs inside it now.
      graph_block = query[/GRAPH datasetgraph:\S+\s*\{(.*)\}\s*\}\s*\z/m, 1]
      expect(graph_block).to include('dcterms:modified')
      expect(graph_block).to include('dcterms:created')
      expect(graph_block).to include('dcterms:type cbgp:personnel_project')
    end
  end

  describe 'CBGP::Dataset.load_from_params_and_write' do
    it 'passes the true form (not the shared dbname) through to the write, for a Personnel submission' do
      allow(CBGP::Dataset).to receive(:write_dataset_to_db)
      # personnel_project's real ORCID cross-references (beneficiary_orcid,
      # personnel_project_responsible_pi_orcid) call get_primary_id via a
      # live SPARQL endpoint if not stubbed - this suite must never depend
      # on that.
      allow(CBGP::Dataset).to receive(:get_primary_id).and_return(nil)
      params = {
        'database' => 'project',
        'primary_id' => '',
        'project_title' => 'A Personnel Project',
        'beneficiary_orcid' => '0000-0001-2345-6789',
        'personnel_project_responsible_pi_orcid' => '0000-0001-2345-6789',
        'personnel_project_total_funding' => '1000.00',
        'project_funding_entity' => 'Test Funding Entity',
        'project_affiliation' => 'affiliation_upm',
        'project_application_code' => 'TEST-CODE',
        'project_dni_nie_pas' => '12345678A',
        'project_internal_code' => 'TEST-INTERNAL',
        'project_start_date' => '2026-01-01',
        'project_end_date' => '2026-12-31'
      }

      CBGP::Dataset.load_from_params_and_write(params: params, form: 'personnel_project')

      expect(CBGP::Dataset).to have_received(:write_dataset_to_db).with(
        hash_including(form: 'personnel_project')
      )
    end
  end
end
