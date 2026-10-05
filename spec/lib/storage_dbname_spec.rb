# frozen_string_literal: true

# Records must be written under their form's shared local:dbname, not under
# the form class name. load_from_params_and_write builds the Dataset with
# type: <form> (to get that form's fields), and write_dataset_to_db_query
# used to take the storage "database" straight from dataset.form_type - so a
# personnel_project was stored at .../personnel_project/context/<id> with
# rdf:type cbgp:personnel_project, and a search of the dbname "project"
# (which is what the search screens and every cross-reference lookup use)
# found none of it. Found 2026-10-05 by a live smoke test of the Funding
# Commitment xrefs; it never showed before only because the sandbox had no
# project records at all.
RSpec.describe 'storage dbname of written records' do
  def written(form, fill)
    ds = CBGP::Dataset.new(type: form)
    ds.primary_id = 'rec-1'
    fill.call(ds)
    write_dataset_to_db_query(dataset: ds, form: form)[:query]
  end

  it 'writes a form that shares a dbname under that dbname' do
    q = written('personnel_project', ->(ds) { ds.title = 'T' })
    expect(q).to include("PREFIX datasetgraph: <#{BASE_URI}project/context/>")
    expect(q).to include('rdf:type cbgp:project ;')
    expect(q).not_to include("#{BASE_URI}personnel_project/")
  end

  it 'still stamps dcterms:type with the true form, not the dbname' do
    q = written('personnel_project', ->(ds) { ds.title = 'T' })
    expect(q).to include('dcterms:type cbgp:personnel_project')
  end

  it 'writes the commitment form under its own dbname' do
    q = written('funding_commitment', ->(ds) { ds.percentage = '50' })
    expect(q).to include("PREFIX datasetgraph: <#{BASE_URI}commitment/context/>")
  end

  it 'leaves a form whose dbname equals its name unchanged' do
    q = written('member', ->(ds) { ds.name = 'N' })
    expect(q).to include("PREFIX datasetgraph: <#{BASE_URI}member/context/>")
  end

  describe '#storage_dbname_for' do
    it 'maps a form to its dbname' do
      expect(storage_dbname_for('european_research_project')).to eq('project')
    end

    it 'returns a dbname, or an unknown name, unchanged instead of raising' do
      expect(storage_dbname_for('project')).to eq('project')
      expect(storage_dbname_for('no_such_thing')).to eq('no_such_thing')
    end
  end

  describe 'upsert lookup by an external primary id (load_from_params_and_write)' do
    let(:params) do
      {
        'database' => 'project', 'primary_id' => '', 'project_title' => 'T',
        'beneficiary_nie' => '12345678Z', 'personnel_project_responsible_pi_nie' => '12345678Z',
        'personnel_project_total_funding' => '1000.00', 'project_funding_entity' => 'F',
        'project_affiliation' => 'affiliation_upm', 'project_application_url' => 'https://example.org/call/C',
        'project_dni_nie_pas' => '12345678A', 'project_internal_code' => %w[A-1 B-2],
        'project_start_date' => '2026-01-01', 'project_end_date' => '2026-12-31'
      }
    end

    before { allow(CBGP::Dataset).to receive(:write_dataset_to_db) }

    def stub_lookup(&block)
      allow(CBGP::Dataset).to receive(:get_primary_id) do |*args, **kw|
        block.call(kw.empty? ? args.last : kw)
      end
    end

    it 'searches the shared dbname, not the form class, one value at a time' do
      calls = []
      stub_lookup { |o| calls << [o[:questionvalue], o[:dataset_type]] && nil }
      CBGP::Dataset.load_from_params_and_write(params: params, form: 'personnel_project')
      expect(calls).to include(%w[A-1 project], %w[B-2 project])
      expect(calls.map(&:last).uniq).to eq(['project'])
    end

    it 'adopts the first existing record any of the values matches' do
      stub_lookup { |o| o[:questionvalue] == 'B-2' ? 'existing-id' : nil }
      ds = CBGP::Dataset.load_from_params_and_write(params: params, form: 'personnel_project')
      expect(ds.primary_id).to eq('existing-id')
    end

    it 'creates a new record when nothing matches' do
      stub_lookup { |_o| nil }
      ds = CBGP::Dataset.load_from_params_and_write(params: params, form: 'personnel_project')
      expect(ds.primary_id).to match(/\A\h{8}-/)
    end
  end

  describe 'search scope (a form searches its dbname, restricted to its own records)' do
    let(:params) { { 'project_internal_code' => 'UI-PROJ-1' } }

    it 'looks under the dbname and keeps only that form\'s records when given a form' do
      q = build_search_query(search_params: params, dataset_type: 'personnel_project')
      expect(q).to include("PREFIX datasetgraph: <#{BASE_URI}project/context/>")
      expect(q).to include('?dataset a cbgp:project .')
      expect(q).to include('?datasetgraph dcterms:type cbgp:personnel_project .')
      expect(q).not_to include('a cbgp:personnel_project')
    end

    it 'does not restrict by form when given the dbname itself (all sharing forms)' do
      q = build_search_query(search_params: params, dataset_type: 'project')
      expect(q).to include('?dataset a cbgp:project .')
      expect(q).not_to include('dcterms:type cbgp:')
    end

    it 'does not restrict a form whose dbname is its own name' do
      q = build_search_query(search_params: { 'member_surnames' => 'x' }, dataset_type: 'member')
      expect(q).to include('?dataset a cbgp:member .')
      expect(q).not_to include('dcterms:type cbgp:')
    end

    it 'applies the same scoping to a broad (all records) search' do
      form_q = search_all_graphs_query(dataset_type: 'personnel_project')
      db_q = search_all_graphs_query(dataset_type: 'project')
      expect(form_q).to include('?s a cbgp:project', '?datasetgraph dcterms:type cbgp:personnel_project .')
      expect(db_q).to include('?s a cbgp:project')
      expect(db_q).not_to include('dcterms:type cbgp:')
    end

    it 'rejects a malicious form name before it reaches SPARQL' do
      expect { form_scope_pattern('x . } DROP') }.to raise_error(StandardError)
    end
  end
end
