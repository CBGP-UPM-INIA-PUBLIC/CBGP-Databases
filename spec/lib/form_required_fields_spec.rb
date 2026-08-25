# frozen_string_literal: true

# Covers the per-form required-fields mechanism (2026-07-28): a form can mark
# one of its fields mandatory via the ontology's local:requires-field
# property, without that requirement living on the shared question class
# itself.
#
# Sara's 2026-08 project-fields restructuring replaced the old shared
# "project" form (Research vs Personnel, distinguished by dcterms:type) with
# several distinct per-funding-type forms. national_regional_research_project
# stands in for "Research" here, personnel_project for "Personnel" - unlike
# before, each now requires a whole list of fields, not just one, so this
# spec picks one example field unique to each side (present, and required, on
# only that form) to prove the mechanism is genuinely per-form:
#   - cbgp:national_regional_research_project (Research) requires project_pi_orcid
#     (a member-ORCID cross-reference; personnel_project doesn't have this field at all)
#   - cbgp:personnel_project (Personnel) requires personnel_project_total_funding
#     (national_regional_research_project doesn't have this field at all)
RSpec.describe 'per-form required fields' do
  # project_pi_orcid is a cross-reference field (references member via
  # member_orcid) - validate_references calls execute_search -> a live
  # SPARQL endpoint if not stubbed, which this suite must never depend on.
  before { allow(CBGP::Dataset).to receive(:get_primary_id).and_return(nil) }

  before do
    {
      'national_regional_research_project' => 'project_pi_orcid',
      'personnel_project' => 'personnel_project_total_funding'
    }.each do |form, qc|
      field = CBGP::Dataset.fields_for(form).find { |f| f[:questionclass] == qc }
      raise "fixture ontology no longer has '#{qc}' on '#{form}' - update this spec" unless field
    end
  end

  describe '#get_form_required_fields_query / .form_required_fields' do
    it 'resolves the Research form (national_regional_research_project) to its full required set' do
      expect(CBGP::Dataset.form_required_fields(form: 'national_regional_research_project')).to eq(Set[
        'national_regional_research_funding_institution',
        'project_application_code',
        'project_call_for_proposal_title',
        'project_dni_nie_pas',
        'project_end_date',
        'project_internal_code',
        'project_pi_orcid',
        'project_start_date',
        'project_title'
      ])
    end

    it 'resolves the Personnel form to its full required set, not overlapping on the Research-only field' do
      required = CBGP::Dataset.form_required_fields(form: 'personnel_project')
      expect(required).to include('personnel_project_total_funding')
      expect(required).not_to include('project_pi_orcid')
    end

    it 'returns an empty set for a form with no local:requires-field at all' do
      expect(CBGP::Dataset.form_required_fields(form: 'member')).to eq(Set.new)
    end

    it 'returns an empty set for a nonexistent form class rather than raising' do
      expect(CBGP::Dataset.form_required_fields(form: 'not_a_real_form')).to eq(Set.new)
    end
  end

  describe '.load_from_params_and_write required-field enforcement' do
    # Every other field national_regional_research_project/personnel_project
    # requires must be supplied too, so a test can omit exactly one field and
    # get a clean, single-field ValidationError - not a pile of unrelated
    # "X is required" errors on top of whatever's actually under test.
    let(:research_params) do
      {
        'database' => 'national_regional_research_project',
        'primary_id' => '',
        'project_title' => 'A Research Project',
        'project_pi_orcid' => '0000-0001-2345-6789',
        'national_regional_research_funding_institution' => 'placeholder',
        'project_application_code' => 'TEST-CODE',
        'project_call_for_proposal_title' => 'Test Call',
        'project_dni_nie_pas' => '12345678A',
        'project_internal_code' => 'TEST-INTERNAL',
        'project_start_date' => '2026-01-01',
        'project_end_date' => '2026-12-31'
      }
    end

    let(:personnel_params) do
      {
        'database' => 'personnel_project',
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
    end

    context 'on the Research form (project_pi_orcid required)' do
      it 'raises ValidationError naming PI ORCiD when project_pi_orcid is missing' do
        params = research_params.reject { |k, _| k == 'project_pi_orcid' }
        expect { CBGP::Dataset.load_from_params_and_write(params: params, form: 'national_regional_research_project') }
          .to raise_error(CBGP::Dataset::ValidationError) do |e|
            expect(e.errors).to contain_exactly(hash_including(label: 'PI ORCiD', message: 'PI ORCiD is required'))
          end
      end

      it 'writes successfully once every required field is supplied' do
        allow(CBGP::Dataset).to receive(:write_dataset_to_db)
        expect { CBGP::Dataset.load_from_params_and_write(params: research_params, form: 'national_regional_research_project') }
          .not_to raise_error
      end

      it 'does not require personnel_project_total_funding, which is Personnel-only' do
        allow(CBGP::Dataset).to receive(:write_dataset_to_db)
        dataset = CBGP::Dataset.load_from_params_and_write(params: research_params, form: 'national_regional_research_project')
        expect(dataset.title).to eq('A Research Project')
      end
    end

    context 'on the Personnel form (personnel_project_total_funding required)' do
      it 'raises ValidationError naming Total funding when personnel_project_total_funding is missing' do
        params = personnel_params.reject { |k, _| k == 'personnel_project_total_funding' }
        expect { CBGP::Dataset.load_from_params_and_write(params: params, form: 'personnel_project') }
          .to raise_error(CBGP::Dataset::ValidationError) do |e|
            expect(e.errors).to contain_exactly(
              hash_including(label: 'Total funding', message: 'Total funding is required')
            )
          end
      end

      it 'does not require project_pi_orcid, which is Research-only' do
        allow(CBGP::Dataset).to receive(:write_dataset_to_db)
        expect do
          CBGP::Dataset.load_from_params_and_write(params: personnel_params, form: 'personnel_project')
        end.not_to raise_error
      end

      it 'writes successfully once every required field is supplied' do
        allow(CBGP::Dataset).to receive(:write_dataset_to_db)
        dataset = CBGP::Dataset.load_from_params_and_write(params: personnel_params, form: 'personnel_project')
        expect(dataset.total_funding).to eq('1000.00')
      end
    end

    it 'falls back to params["database"] as the effective form when form: is not given' do
      # national_regional_research_project's dbname is "project" but its own
      # class name is what fields_for/requires-field actually key off of, so
      # this only exercises the fallback cleanly when params["database"] is
      # itself a real form class name, same as personnel_project already is
      # elsewhere in this file.
      params = research_params.reject { |k, _| k == 'project_pi_orcid' }
      expect { CBGP::Dataset.load_from_params_and_write(params: params) }
        .to raise_error(CBGP::Dataset::ValidationError) do |e|
          expect(e.errors).to contain_exactly(hash_including(label: 'PI ORCiD', message: 'PI ORCiD is required'))
        end
    end
  end

  describe 'Questionnaire#required flag (drives the visual asterisk in _question.erb)' do
    def find_question(questionnaire, questionid)
      questionnaire.sections.flat_map(&:questions).find { |q| q.questionid == questionid }
    end

    it 'marks project_pi_orcid required on the Research questionnaire' do
      questionnaire = Questionnaire.new(questionnaire_type: 'national_regional_research_project')
      expect(find_question(questionnaire, 'project_pi_orcid').required).to be true
    end

    it 'has no personnel_project_total_funding question at all on the Research questionnaire' do
      questionnaire = Questionnaire.new(questionnaire_type: 'national_regional_research_project')
      expect(find_question(questionnaire, 'personnel_project_total_funding')).to be_nil
    end

    it 'marks personnel_project_total_funding required on the Personnel questionnaire' do
      questionnaire = Questionnaire.new(questionnaire_type: 'personnel_project')
      expect(find_question(questionnaire, 'personnel_project_total_funding').required).to be true
    end

    it 'has no project_pi_orcid question at all on the Personnel questionnaire' do
      questionnaire = Questionnaire.new(questionnaire_type: 'personnel_project')
      expect(find_question(questionnaire, 'project_pi_orcid')).to be_nil
    end

    it 'leaves every question unrequired for a form with no local:requires-field at all' do
      questionnaire = Questionnaire.new(questionnaire_type: 'member')
      expect(questionnaire.sections.flat_map(&:questions).map(&:required)).to all(be false)
    end
  end
end
