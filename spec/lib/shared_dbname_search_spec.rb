# frozen_string_literal: true

require 'rack/test'
require_relative '../../app/controllers/application_controller'

# Searching across all the forms that store under one dbname (an institute's
# four project forms all store under "project"). The code is generic: the unit
# tests below use made-up form and dbname names, and only the integration part
# touches the real ontology.
RSpec.describe 'searching a dbname several forms share' do
  def fld(questionclass, sequence)
    { questionclass: questionclass, sequence: sequence, label: questionclass }
  end

  describe 'with made-up forms' do
    let(:forms) { %w[alpha_form beta_form] }
    let(:fields) do
      { 'alpha_form' => [fld('shared_a', 1), fld('only_alpha', 2), fld('shared_b', 3)],
        'beta_form' => [fld('shared_b', 1), fld('shared_a', 2), fld('only_beta', 3)] }
    end

    before do
      # a top-level method, called from inside CBGP::Dataset too: stubbed on Object
      allow_any_instance_of(Object).to receive(:forms_sharing_dbname) { |_o, *args, **kw| (kw.empty? ? args.last : kw)[:dbname] == 'widgets' ? forms : [] }
      allow(CBGP::Dataset).to receive(:fields_for) do |type|
        type == 'widgets' ? (fields['alpha_form'] + fields['beta_form']).uniq { |f| f[:questionclass] }.sort_by { |f| f[:sequence] } : fields.fetch(type, [])
      end
    end

    describe '#shared_dbname?' do
      it 'is true for a name more than one form is stored under' do
        expect(shared_dbname?('widgets')).to be(true)
      end

      it 'is false for a name only one form (or none) uses' do
        allow_any_instance_of(Object).to receive(:forms_sharing_dbname).and_return(['alpha_form'])
        expect(shared_dbname?('alpha_form')).to be(false)
        allow_any_instance_of(Object).to receive(:forms_sharing_dbname).and_return([])
        expect(shared_dbname?('nothing')).to be(false)
      end

      it 'is false when the name is itself one of the forms' do
        allow_any_instance_of(Object).to receive(:forms_sharing_dbname).and_return(%w[alpha_form beta_form])
        expect(shared_dbname?('alpha_form')).to be(false)
      end

      it 'is false, not an error, for a name that is not a safe identifier' do
        allow_any_instance_of(Object).to receive(:forms_sharing_dbname).and_call_original
        expect(shared_dbname?('x" } #')).to be(false)
      end
    end

    describe 'CBGP::Dataset.common_fields_for' do
      it 'keeps only the fields every form has, once each, in question order' do
        expect(CBGP::Dataset.common_fields_for('widgets').map { |f| f[:questionclass] }).to eq(%w[shared_a shared_b])
      end

      it 'leaves fields_for as the union (what cross-references and record loading need)' do
        expect(CBGP::Dataset.fields_for('widgets').map { |f| f[:questionclass] })
          .to contain_exactly('shared_a', 'only_alpha', 'shared_b', 'only_beta')
      end

      it 'is just fields_for for a name that is not shared' do
        allow_any_instance_of(Object).to receive(:forms_sharing_dbname).and_return(['alpha_form'])
        expect(CBGP::Dataset.common_fields_for('alpha_form')).to eq(fields['alpha_form'])
      end
    end

    describe '#search_fields_for and #search_field_restriction' do
      it 'limit a shared dbname to the common fields' do
        expect(search_fields_for('widgets').map { |f| f[:questionclass] }).to eq(%w[shared_a shared_b])
        expect(search_field_restriction('widgets')).to eq(Set.new(%w[shared_a shared_b]))
      end

      it 'leave an ordinary form alone' do
        allow_any_instance_of(Object).to receive(:forms_sharing_dbname).and_return(['alpha_form'])
        expect(search_fields_for('alpha_form')).to eq(fields['alpha_form'])
        expect(search_field_restriction('alpha_form')).to be_nil
      end
    end

    describe '#shared_dbname_entries' do
      let(:databases) { [['Alpha', 'alpha_form'], ['Beta', 'beta_form'], ['Gamma', 'gamma_form']] }

      before do
        allow(self).to receive(:storage_dbname_for) { |form| { 'alpha_form' => 'widgets', 'beta_form' => 'widgets' }.fetch(form, form) }
      end

      it 'adds one entry per shared dbname, none for forms that store alone' do
        expect(shared_dbname_entries(databases, language: 'en').map(&:last)).to eq(['widgets'])
      end

      it 'falls back to a generic "(all types)" name when the ontology has no text for that dbname' do
        expect(shared_dbname_entries(databases, language: 'en').first.first).to eq('widgets (all types)')
        expect(shared_dbname_entries(databases, language: 'es').first.first).to eq('widgets (todos los tipos)')
      end
    end
  end

  describe 'Questionnaire#restrict_to_fields!' do
    Q = Struct.new(:questionid)

    it 'keeps each wanted question once across sections and drops sections left empty' do
      sec = Struct.new(:questions)
      questionnaire = Questionnaire.allocate
      questionnaire.instance_variable_set(
        :@sections,
        [sec.new([Q.new('a'), Q.new('x')]), sec.new([Q.new('a'), Q.new('b')]), sec.new([Q.new('x')])]
      )

      questionnaire.restrict_to_fields!(Set.new(%w[a b]))

      kept = questionnaire.instance_variable_get(:@sections)
      expect(kept.map { |s| s.questions.map(&:questionid) }).to eq([['a'], ['b']])
    end
  end

  describe 'with the real ontology (the shared "project" dbname)' do
    it 'recognises project as shared, and no single form as one' do
      expect(shared_dbname?('project')).to be(true)
      expect(shared_dbname?('personnel_project')).to be(false)
      expect(shared_dbname?('member')).to be(false)
    end

    it 'offers only what every project form has' do
      common = CBGP::Dataset.common_fields_for('project').map { |f| f[:questionclass] }
      expect(common).to include('project_title', 'project_start_date', 'project_end_date', 'project_status')
      expect(common).not_to include('project_pi_nie', 'personnel_project_total_funding')
    end

    it 'counts only the Core forms, not the cut-down user-facing one that shares the dbname' do
      expect(forms_sharing_dbname(dbname: 'project')).to include('personnel_project', 'european_research_project')
      expect(forms_sharing_dbname(dbname: 'project')).not_to include('userproject')
      expect(forms_sharing_dbname(dbname: 'project', category: 'UserFacing')).to eq(['userproject'])
    end

    it 'is named by the ontology, in both languages' do
      expect(dbname_label('project', language: 'en')).to eq('Projects (all types)')
      expect(dbname_label('project', language: 'es')).to eq('Proyectos (todos los tipos)')
    end

    it 'adds the all-types entry to what can be queried, from the forms that can be added' do
      databases = get_databases(type: 'Core', language: 'en')
      entries = shared_dbname_entries(databases, language: 'en')
      expect(entries).to include(['Projects (all types)', 'project'])
      expect(databases.map(&:last)).not_to include('project') # not itself addable
    end
  end

  describe 'in the pages', type: :request do
    include Rack::Test::Methods

    def app
      CBGP::DatabasesApp
    end

    before do
      header 'Host', 'localhost'
      post '/cbgp/login', username: 'test-admin', password: 'test'
    end

    def select_block(id)
      last_response.body[%r{<select[^>]*id="#{id}".*?</select>}m]
    end

    it 'lists the all-types entry under Query data but not under Add data' do
      get '/cbgp/dashboard'

      expect(select_block('query_database')).to include('<option value="project">Projects (all types)</option>')
      expect(select_block('use_form')).not_to include('value="project"')
      expect(select_block('use_form')).to include('value="personnel_project"')
    end

    it 'shows the all-types search form only the fields every form has, and the Show all records link' do
      get '/cbgp/search-dataset/project'

      expect(last_response.body).to include('name="project_title"')
      expect(last_response.body).to include('name="project_end_date[start]"')
      expect(last_response.body).not_to include('project_pi_nie') # a field only some project forms have
      expect(last_response.body).to include('href="/cbgp/query-dataset/project?__all=1"')
      expect(last_response.body).to include('Show all records')
    end

    it 'still shows a single form its own, wider, field list' do
      get '/cbgp/search-dataset/european_research_project'

      expect(last_response.body).to include('project_pi_nie')
    end

    it 'offers an "or no value" tick box beside every searchable field' do
      get '/cbgp/search-dataset/project'

      expect(last_response.body).to include('name="project_end_date__orempty"')
      expect(last_response.body).to include('or no value')
    end
  end
end
