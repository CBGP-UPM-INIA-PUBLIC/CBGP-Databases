# frozen_string_literal: true

# Every field that names a person must be a cross-reference to Member that is
# SEARCHED by surname but STORES the member's DNI/NIE/PAS (not every member has
# an ORCID, and administrators don't carry NIEs in their heads). One place to
# fail loudly if a person field is ever added/reverted as a plain text box, or
# keyed on ORCID again.
#
# publication_cbgp_authors is deliberately the exception: it stays on ORCID,
# because DOI metadata only ever supplies ORCIDs, and an admin must give a
# member an ORCID before that authorship link can be made.
RSpec.describe 'person fields are member cross-references keyed on DNI/NIE/PAS' do
  PERSON_FIELDS = {
    'national_regional_research_project' => %w[project_pi_nie project_main_copi_nie],
    'european_research_project' => %w[project_pi_nie project_main_copi_nie],
    'private_research_project' => %w[project_pi_nie project_main_copi_nie],
    'personnel_project' => %w[beneficiary_nie project_pi_nie],
    'funding_commitment' => %w[commitment_member]
  }.freeze

  PERSON_FIELDS.each do |form, questionclasses|
    questionclasses.each do |qc|
      it "#{form}: #{qc} searches members by surname and stores their DNI/NIE/PAS" do
        field = CBGP::Dataset.fields_for(form).find { |f| f[:questionclass] == qc }
        expect(field).not_to be_nil
        expect(field[:references_target]).to eq('member')
        expect(field[:references_via]).to end_with('#member_dni_nie_pas')
        expect(field[:references_label]).to eq('member_surnames')
      end
    end
  end

  it 'keeps publication authors on ORCID' do
    field = CBGP::Dataset.fields_for('publication').find { |f| f[:questionclass] == 'publication_cbgp_authors' }
    expect(field[:references_via]).to end_with('#member_orcid')
  end

  it 'surfaces the xref to the questionnaire (so the search form gets the typeahead too)' do
    q = Questionnaire.new(questionnaire_type: 'personnel_project')
    question = q.sections.flat_map(&:questions).find { |x| x.questionid == 'beneficiary_nie' }
    expect(question.references_target).to eq('member')
    expect(question.references_via_class).to eq('member_dni_nie_pas')
  end
end
