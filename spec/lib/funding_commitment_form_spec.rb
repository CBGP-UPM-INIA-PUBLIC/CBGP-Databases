# frozen_string_literal: true

# Covers the Funding Commitment form (cbgp:funding_commitment, dbname
# "commitment"): one record = what percentage of one member's salary cost is
# charged to one project, over a date range. Entirely ontology-driven - these
# specs exist to catch the ontology and the engine drifting apart (e.g. the
# xref target "project" is a shared dbname, not a form class; see
# spec/lib/fields_for_dbname_fallback_spec.rb), not to test commitment-specific
# code, because there is none.
RSpec.describe 'Funding Commitment form' do
  # Same reasoning as spec/lib/form_required_fields_spec.rb: the member/project
  # cross-reference lookups would otherwise hit a live SPARQL endpoint.
  before { allow(CBGP::Dataset).to receive(:get_primary_id).and_return(nil) }

  let(:params) do
    {
      'database' => 'funding_commitment',
      'primary_id' => '',
      'commitment_member' => '12345678Z',
      'commitment_project' => 'INT-001',
      'commitment_percentage' => '50',
      'commitment_start_date' => '2026-01-01'
    }
  end

  def field(questionclass)
    CBGP::Dataset.fields_for('funding_commitment').find { |f| f[:questionclass] == questionclass }
  end

  it 'is a Core (admin) form stored under its own dbname' do
    expect(get_dbname_for_form(form: 'funding_commitment')).to eq('commitment')
    core = get_questionnaire_types_query(type: 'Core').map { |t| t[:questionnaire_type].to_s.split('#').last }
    expect(core).to include('funding_commitment')
    user_facing = get_questionnaire_types_query(type: 'UserFacing').map { |t| t[:questionnaire_type].to_s.split('#').last }
    expect(user_facing).not_to include('funding_commitment')
  end

  it 'requires member, project, percentage and start date - but not end date or notes' do
    expect(CBGP::Dataset.form_required_fields(form: 'funding_commitment')).to eq(Set[
      'commitment_member', 'commitment_project', 'commitment_percentage', 'commitment_start_date'
    ])
  end

  describe 'cross-reference wiring' do
    it 'points the member field at member, stored by DNI/NIE/PAS and labelled by surname' do
      f = field('commitment_member')
      expect(f[:references_target]).to eq('member')
      expect(f[:references_via]).to end_with('#member_dni_nie_pas')
    end

    it 'points the project field at the shared "project" dbname, stored by internal code' do
      f = field('commitment_project')
      expect(f[:references_target]).to eq('project')
      expect(f[:references_via]).to end_with('#project_internal_code')
    end

    it 'resolves both xref key classes to real methods on their (multi-form) targets' do
      expect(CBGP::Dataset.resolve_key_method('member', 'member_dni_nie_pas')).to eq('dni_nie_pas')
      expect(CBGP::Dataset.resolve_key_method('project', 'project_internal_code')).to eq('int_project_code')
    end

    it 'can build a Dataset on the xref target dbname (no zero-field Dataset)' do
      expect(CBGP::Dataset.new(type: 'project')).to respond_to(:title, :int_project_code)
    end
  end

  describe 'percentage field' do
    it 'uses the plain-number widget and Number class' do
      f = field('commitment_percentage')
      expect(f[:class]).to eq('number')
      expect(f[:widget]).to end_with('#number')
    end

    it 'stores a canonical decimal' do
      allow(CBGP::Dataset).to receive(:write_dataset_to_db)
      ds = CBGP::Dataset.load_from_params_and_write(params: params.merge('commitment_percentage' => '33.5'),
                                                   form: 'funding_commitment')
      expect(ds.percentage).to eq('33.50')
    end

    it 'rejects text' do
      expect { CBGP::Dataset.load_from_params_and_write(params: params.merge('commitment_percentage' => 'half'),
                                                       form: 'funding_commitment') }
        .to raise_error(CBGP::Dataset::ValidationError)
    end
  end

  describe 'saving' do
    it 'writes with only the required fields (end date open)' do
      allow(CBGP::Dataset).to receive(:write_dataset_to_db)
      ds = CBGP::Dataset.load_from_params_and_write(params: params, form: 'funding_commitment')
      expect(ds.start_date).to eq('2026-01-01')
      expect(ds.end_date.to_s).to eq('')
    end

    %w[commitment_member commitment_project commitment_percentage commitment_start_date].each do |qc|
      it "raises ValidationError when #{qc} is missing" do
        expect { CBGP::Dataset.load_from_params_and_write(params: params.reject { |k, _| k == qc },
                                                         form: 'funding_commitment') }
          .to raise_error(CBGP::Dataset::ValidationError) do |e|
            expect(e.errors.size).to eq(1)
          end
      end
    end

    it 'rejects an unparseable date' do
      expect { CBGP::Dataset.load_from_params_and_write(params: params.merge('commitment_end_date' => 'next spring'),
                                                       form: 'funding_commitment') }
        .to raise_error(CBGP::Dataset::ValidationError)
    end
  end
end

# Every form must appear in its menu. The dashboard query used to match
# local:form-category "Core"@en exactly, so a form whose category was written
# without the @en tag (the European and Private project forms) vanished from
# the Add and Query menus with no error. Found 2026-10-05 by the "required on
# every form" test failing to see the European form.
RSpec.describe 'forms listed in the menus' do
  def listed(type)
    get_questionnaire_types_query(type: type).map { |t| t[:questionnaire_type].to_s.split('#').last }
  end

  it 'lists every Core form, including all four project forms' do
    expect(listed('Core')).to include(
      'member', 'publication', 'funding_commitment',
      'european_research_project', 'national_regional_research_project', 'private_research_project', 'personnel_project'
    )
  end

  it 'lists the user-facing project form only under UserFacing' do
    expect(listed('UserFacing')).to include('userproject')
    expect(listed('Core')).not_to include('userproject')
  end

  it 'does not depend on a language tag (a category with no @en still counts)' do
    q = RDF::Statement.new(RDF::URI('https://w3id.org/CBGP-App#__probe'), RDF::URI('urn:local:form-category'), RDF::Literal('Core'))
    sub = RDF::Statement.new(RDF::URI('https://w3id.org/CBGP-App#__probe'), RDF::RDFS.subClassOf, RDF::URI('https://w3id.org/CBGP-App#forms'))
    lab = RDF::Statement.new(RDF::URI('https://w3id.org/CBGP-App#__probe'), RDF::RDFS.label, RDF::Literal('Probe', language: :en))
    $ontology << q << sub << lab
    expect(listed('Core')).to include('__probe')
  ensure
    [q, sub, lab].each { |st| $ontology.delete(st) }
  end

  it 'shows a form tagged either way' do
    expect(get_databases(type: 'Core', language: 'en').map(&:last)).to include('european_research_project', 'private_research_project')
  end
end
