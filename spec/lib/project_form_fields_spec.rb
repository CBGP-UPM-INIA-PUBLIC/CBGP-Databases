# frozen_string_literal: true

# Fields removed from the project forms (2026-10-06), so they do not creep back:
# - project_type: the kind of project is decided by the curators who classify a
#   submitted application, not by the submitter (see spec/curate_as_spec.rb);
#   what the funding is is already captured by the funding institution.
# - project_dni_nie_pas: a project has no "project-level" person. People are
#   linked through the beneficiary (Personnel), the PI and co-PI (research
#   projects) and funding commitments - all member cross-references.
RSpec.describe 'project form fields' do
  forms = %w[userproject european_research_project national_regional_research_project
             private_research_project personnel_project]

  forms.each do |form|
    it "#{form} has no project_type and no project-level DNI/NIE/PAS" do
      questionclasses = CBGP::Dataset.fields_for(form).map { |f| f[:questionclass] }

      expect(questionclasses).not_to include('project_type', 'project_dni_nie_pas')
    end
  end

  it 'requires no project-level DNI/NIE/PAS on any Core project form' do
    forms.each do |form|
      expect(CBGP::Dataset.form_required_fields(form: form)).not_to include('project_dni_nie_pas')
    end
  end

  it 'still links people to a project through member cross-references' do
    expect(CBGP::Dataset.fields_for('personnel_project').map { |f| f[:questionclass] }).to include('beneficiary_nie')
    expect(CBGP::Dataset.fields_for('european_research_project').map { |f| f[:questionclass] }).to include('project_pi_nie')
  end

  it 'has ONE PI field shared by every project form, the user form included: a member cross-reference, required' do
    forms.each do |form|
      field = CBGP::Dataset.fields_for(form).find { |f| f[:questionclass] == 'project_pi_nie' }

      expect(field).not_to be_nil, "#{form} has no project_pi_nie"
      expect(field[:references_target]).to eq('member')
      expect(CBGP::Dataset.form_required_fields(form: form)).to include('project_pi_nie')
    end
  end

  it 'no longer has a separate PI field for Personnel projects' do
    forms.each do |form|
      expect(CBGP::Dataset.fields_for(form).map { |f| f[:questionclass] }).not_to include('personnel_project_responsible_pi_nie')
    end
  end

  it 'has a free-text Comments field on every project form, the user form included, never required' do
    forms.each do |form|
      field = CBGP::Dataset.fields_for(form).find { |f| f[:questionclass] == 'project_comments' }

      expect(field).not_to be_nil, "#{form} has no project_comments"
      expect(field[:widget]).to end_with('#textfield') # a multi-line box
      expect(CBGP::Dataset.form_required_fields(form: form)).not_to include('project_comments')
    end
  end

  it 'carries a submitter\'s comment over when the record is curated under any Core form' do
    source = CBGP::Dataset.new(type: 'userproject')
    field = source.fields.find { |f| f[:questionclass] == 'project_comments' }
    source.public_send("#{field[:method]}=", "Please note the deadline.\nThank you.")
    allow(CBGP::Dataset).to receive(:load_from_primary_id).and_return(source)

    (forms - ['userproject']).each do |form|
      expect(values_not_carried(from_form: 'userproject', to_form: form, primary_id: 'x').map(&:first)).not_to include('Comments')
    end
  end
end
