# frozen_string_literal: true

# Covers the per-form required-fields mechanism (2026-07-28): a form can mark
# one of its fields mandatory via the ontology's local:requires-field
# property, without that requirement living on the shared question class
# itself.
#
# Deliberately parallel to spec/lib/form_defaults_spec.rb in shape (per-form
# resolution via a queries.rb SPARQL query + a dataset_classes.rb wrapper),
# but the two forms here don't actually share a required field in this
# fixture - the Research and Personnel Project forms only overlap on
# project_category (see form_defaults_spec.rb), and it turns out Personnel
# Project has no project_title field at all (it's not a member of
# new-personnel-project-questions), so there's nothing to require there.
# Each form instead requires a field that's genuinely its own:
#   - cbgp:project (Research)            requires project_title
#   - cbgp:personnel_project (Personnel) requires project_annual_income
# That's still enough to prove the mechanism is genuinely per-form (each
# form's requirement is independent and doesn't leak onto the other), just
# via two different fields rather than one shared one.
RSpec.describe 'per-form required fields' do
  before do
    %w[project_title project_annual_income].each do |qc|
      field = CBGP::Dataset.fields_for('project').find { |f| f[:questionclass] == qc }
      raise "fixture ontology no longer has '#{qc}' - update this spec" unless field
    end
  end

  describe '#get_form_required_fields_query / .form_required_fields' do
    it 'resolves the Research form to just project_title' do
      expect(CBGP::Dataset.form_required_fields(form: 'project')).to eq(Set['project_title'])
    end

    it 'resolves the Personnel form to just project_annual_income' do
      expect(CBGP::Dataset.form_required_fields(form: 'personnel_project')).to eq(Set['project_annual_income'])
    end

    it 'returns an empty set for a form with no local:requires-field at all' do
      expect(CBGP::Dataset.form_required_fields(form: 'member')).to eq(Set.new)
    end

    it 'returns an empty set for a nonexistent form class rather than raising' do
      expect(CBGP::Dataset.form_required_fields(form: 'not_a_real_form')).to eq(Set.new)
    end
  end

  describe '.load_from_params_and_write required-field enforcement' do
    let(:base_params) { { 'database' => 'project', 'primary_id' => '' } }

    context 'on the Research form (project_title required)' do
      it 'raises ValidationError naming Title when project_title is missing' do
        params = base_params
        expect { CBGP::Dataset.load_from_params_and_write(params: params, form: 'project') }
          .to raise_error(CBGP::Dataset::ValidationError) do |e|
            expect(e.errors).to contain_exactly(hash_including(label: 'Title', message: 'Title is required'))
          end
      end

      it 'writes successfully once project_title is supplied' do
        allow(CBGP::Dataset).to receive(:write_dataset_to_db)
        params = base_params.merge('project_title' => 'A Research Project')
        expect { CBGP::Dataset.load_from_params_and_write(params: params, form: 'project') }.not_to raise_error
      end

      it 'does not require project_annual_income, which is Personnel-only' do
        allow(CBGP::Dataset).to receive(:write_dataset_to_db)
        params = base_params.merge('project_title' => 'A Research Project')
        dataset = CBGP::Dataset.load_from_params_and_write(params: params, form: 'project')
        expect(dataset.title).to eq('A Research Project')
      end
    end

    context 'on the Personnel form (project_annual_income required)' do
      it 'raises ValidationError naming Annual income when it is missing' do
        params = base_params
        expect { CBGP::Dataset.load_from_params_and_write(params: params, form: 'personnel_project') }
          .to raise_error(CBGP::Dataset::ValidationError) do |e|
            expect(e.errors).to contain_exactly(
              hash_including(label: 'Annual income', message: 'Annual income is required')
            )
          end
      end

      it 'does not require project_title, which is Research-only' do
        # A blank/missing project_title must NOT raise here, since this
        # form's requires-field set is project_annual_income alone.
        allow(CBGP::Dataset).to receive(:write_dataset_to_db)
        params = base_params.merge('project_annual_income' => '1000.00')
        expect do
          CBGP::Dataset.load_from_params_and_write(params: params, form: 'personnel_project')
        end.not_to raise_error
      end

      it 'writes successfully once project_annual_income is supplied' do
        allow(CBGP::Dataset).to receive(:write_dataset_to_db)
        params = base_params.merge('project_annual_income' => '1000.00')
        dataset = CBGP::Dataset.load_from_params_and_write(params: params, form: 'personnel_project')
        expect(dataset.annual_income).to eq('1000.00')
      end
    end

    it 'falls back to params["database"] as the effective form when form: is not given' do
      # project's dbname and form class are both "project", so this exercises
      # the fallback (form: nil -> effective_form = params['database']) and
      # should behave identically to explicitly passing form: 'project'.
      params = base_params
      expect { CBGP::Dataset.load_from_params_and_write(params: params) }
        .to raise_error(CBGP::Dataset::ValidationError) do |e|
          expect(e.errors).to contain_exactly(hash_including(label: 'Title', message: 'Title is required'))
        end
    end
  end

  describe 'Questionnaire#required flag (drives the visual asterisk in _question.erb)' do
    def find_question(questionnaire, questionid)
      questionnaire.sections.flat_map(&:questions).find { |q| q.questionid == questionid }
    end

    it 'marks project_title required on the Research questionnaire' do
      questionnaire = Questionnaire.new(questionnaire_type: 'project')
      expect(find_question(questionnaire, 'project_title').required).to be true
    end

    it 'marks project_annual_income NOT required on the Research questionnaire' do
      questionnaire = Questionnaire.new(questionnaire_type: 'project')
      question = find_question(questionnaire, 'project_annual_income')
      expect(question&.required).to be_falsey
    end

    it 'marks project_annual_income required on the Personnel questionnaire' do
      questionnaire = Questionnaire.new(questionnaire_type: 'personnel_project')
      expect(find_question(questionnaire, 'project_annual_income').required).to be true
    end

    it 'has no project_title question at all on the Personnel questionnaire' do
      questionnaire = Questionnaire.new(questionnaire_type: 'personnel_project')
      expect(find_question(questionnaire, 'project_title')).to be_nil
    end

    it 'leaves every question unrequired for a form with no local:requires-field at all' do
      questionnaire = Questionnaire.new(questionnaire_type: 'member')
      expect(questionnaire.sections.flat_map(&:questions).map(&:required)).to all(be false)
    end
  end
end
