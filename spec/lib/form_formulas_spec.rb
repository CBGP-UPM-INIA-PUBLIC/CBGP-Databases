# frozen_string_literal: true

# Covers the calculated-field mechanism (2026-07-28): a form can compute one
# of its fields from OTHER field values via the ontology's local:has-formulas
# branch (Dentaku expressions, safe/sandboxed - not Ruby eval), rather than
# asking the user to do the arithmetic themselves and type in the result.
#
# Same form-scoped reification shape as spec/lib/form_defaults_spec.rb (a
# formula is TWO pieces of data per field: which one, and the expression),
# NOT the direct-property shape spec/lib/form_required_fields_spec.rb uses -
# see local:has-formulas' own doc comment in the .owl file for why.
#
# Exercised against the real demo fields (not synthetic ones), which also
# happen to be a genuine DEPENDENCY CHAIN - the actual motivating case that
# forced this feature past a single flat pass:
#   - cbgp:project (Research):  project_overheads      = total_funding * 0.25 ("UPM overheads")
#                                project_cbgp_overheads = project_overheads * 0.05 (chained - depends on the line above)
#   - cbgp:personnel_project:   project_cbgp_overheads = annual_income * 0.08 (same shared field, unrelated formula)
# All percentages are explicitly-marked placeholders pending real
# institutional confirmation - see the .owl file - so this spec asserts the
# MECHANISM works correctly, not that these are the final business numbers.
RSpec.describe 'per-form calculated fields' do
  before do
    %w[project_overheads project_cbgp_overheads project_total_funding project_annual_income].each do |qc|
      field = CBGP::Dataset.fields_for('project').find { |f| f[:questionclass] == qc }
      raise "fixture ontology no longer has '#{qc}' - update this spec" unless field
    end
  end

  describe '#get_form_formulas_query / .form_formulas' do
    # `include`, not `eq`: both forms also carry a separate sandbox
    # project_test_* formula chain (added for manual testing, see the .owl
    # file) alongside the real overheads ones asserted here - this spec
    # only needs to prove THESE two resolve correctly, not that nothing
    # else is declared on the form.
    it 'resolves the Research form to its two-step chain' do
      formulas = CBGP::Dataset.form_formulas(form: 'project')
      expect(formulas).to include(
        'project_overheads' => 'project_total_funding * 0.25',
        'project_cbgp_overheads' => 'project_overheads * 0.05'
      )
    end

    it 'resolves the Personnel form to a different, unrelated formula for the same shared field' do
      formulas = CBGP::Dataset.form_formulas(form: 'personnel_project')
      expect(formulas).to include('project_cbgp_overheads' => 'project_annual_income * 0.08')
    end

    it 'returns an empty hash for a form with no local:has-formulas at all' do
      expect(CBGP::Dataset.form_formulas(form: 'member')).to eq({})
    end

    it 'returns an empty hash for a nonexistent form class rather than raising' do
      expect(CBGP::Dataset.form_formulas(form: 'not_a_real_form')).to eq({})
    end
  end

  describe '.load_from_params_and_write calculated-field evaluation' do
    let(:base_params) { { 'database' => 'project', 'primary_id' => '', 'project_title' => 'Chain Test Project' } }

    before { allow(CBGP::Dataset).to receive(:write_dataset_to_db) }

    it 'resolves the full chain from a single submission of the base field' do
      params = base_params.merge('project_total_funding' => '10000.00')
      dataset = CBGP::Dataset.load_from_params_and_write(params: params, form: 'project')

      expect(dataset.overheads).to eq('2500.00') # 10000 * 0.25
      expect(dataset.cbgp_overheads).to eq('125.00') # 2500  * 0.05 - depends on the line above
    end

    it 'never lets the client-submitted value for a calculated field survive - it is always server-recomputed' do
      # Tampered/forged values for the calculated fields themselves must be
      # completely ignored, since load_from_params_and_write always
      # overwrites them - this is the core trust property of the mechanism.
      params = base_params.merge(
        'project_total_funding' => '10000.00',
        'project_overheads' => '999999.99',
        'project_cbgp_overheads' => '999999.99'
      )
      dataset = CBGP::Dataset.load_from_params_and_write(params: params, form: 'project')

      expect(dataset.overheads).to eq('2500.00')
      expect(dataset.cbgp_overheads).to eq('125.00')
    end

    it 'leaves the whole chain blank when the base dependency is missing, rather than raising or partially computing' do
      dataset = CBGP::Dataset.load_from_params_and_write(params: base_params, form: 'project')

      expect(dataset.overheads).to be_nil.or eq('')
      expect(dataset.cbgp_overheads).to be_nil.or eq('')
    end

    it 'computes the Personnel form field independently of the Research chain' do
      params = { 'database' => 'project', 'primary_id' => '', 'project_annual_income' => '1000.00' }
      dataset = CBGP::Dataset.load_from_params_and_write(params: params, form: 'personnel_project')

      expect(dataset.cbgp_overheads).to eq('80.00') # 1000 * 0.08
      expect(dataset.overheads).to be_nil.or eq('') # no formula for it on this form
    end
  end

  describe 'Questionnaire#formula / #formula_dependencies (drives the read-only _calculated.erb widget)' do
    def find_question(questionnaire, questionid)
      questionnaire.sections.flat_map(&:questions).find { |q| q.questionid == questionid }
    end

    it 'exposes the Research chain formulas, with correctly-extracted dependencies' do
      questionnaire = Questionnaire.new(questionnaire_type: 'project')

      overheads = find_question(questionnaire, 'project_overheads')
      expect(overheads.formula).to eq('project_total_funding * 0.25')
      expect(overheads.formula_dependencies).to eq(%w[project_total_funding])

      cbgp_overheads = find_question(questionnaire, 'project_cbgp_overheads')
      expect(cbgp_overheads.formula).to eq('project_overheads * 0.05')
      expect(cbgp_overheads.formula_dependencies).to eq(%w[project_overheads])
    end

    it "exposes the Personnel form's own unrelated formula for the same shared field" do
      questionnaire = Questionnaire.new(questionnaire_type: 'personnel_project')
      cbgp_overheads = find_question(questionnaire, 'project_cbgp_overheads')
      expect(cbgp_overheads.formula).to eq('project_annual_income * 0.08')
    end

    it 'has no project_overheads question at all on the Personnel questionnaire (not one of its fields)' do
      questionnaire = Questionnaire.new(questionnaire_type: 'personnel_project')
      expect(find_question(questionnaire, 'project_overheads')).to be_nil
    end

    it 'leaves formula nil for an ordinary (non-calculated) question' do
      questionnaire = Questionnaire.new(questionnaire_type: 'project')
      expect(find_question(questionnaire, 'project_title').formula).to be_nil
    end
  end
end
