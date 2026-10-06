# frozen_string_literal: true

# Covers the shared-dbname fallback in get_questionnaire_sections_query
# (lib/queries.rb) and its two callers, CBGP::Dataset.fields_for and
# CBGP::Dataset.key_method_for_form.
#
# Since Sara's project-fields split there is no ontology form class called
# "project" - five forms (european_research_project, personnel_project, ...)
# all store under the dbname "project". Anything that only knows the storage
# table - notably a cross-reference field whose local:references target is
# "project" - used to get a Dataset with zero fields (every getter then
# raised NoMethodError, and the typeahead silently fell back to the record's
# UUID as both value and label). The dbname now resolves to the union of
# its forms' fields instead.
RSpec.describe 'dbname -> fields fallback' do
  def questionclasses(type)
    CBGP::Dataset.fields_for(type).map { |f| f[:questionclass] }
  end

  describe 'CBGP::Dataset.fields_for with a shared dbname' do
    let(:fields) { CBGP::Dataset.fields_for('project') }

    it 'is non-empty even though "project" is not itself a form class' do
      expect(fields).not_to be_empty
    end

    it 'includes fields shared by every project form' do
      expect(questionclasses('project')).to include('project_title', 'project_internal_code')
    end

    it 'includes fields that exist on only one of the forms sharing the dbname' do
      expect(questionclasses('project')).to include('personnel_project_total_funding', 'project_main_copi_nie')
    end

    it 'lists each question class once, not once per form that contains it' do
      qcs = questionclasses('project')
      expect(qcs).to eq(qcs.uniq)
    end

    it 'is sorted by question sequence' do
      sequences = fields.map { |f| f[:sequence] }
      expect(sequences).to eq(sequences.sort)
    end

    it 'gives a Dataset built on the dbname working getters (instead of NoMethodError)' do
      ds = CBGP::Dataset.new(type: 'project')
      expect(ds).to respond_to(:title)
      expect(ds).to respond_to(:int_project_code)
    end
  end

  describe 'a real form class is unaffected' do
    it 'still resolves to just that form\'s own fields' do
      personnel = questionclasses('personnel_project')
      expect(personnel).to include('beneficiary_nie')
      expect(personnel).not_to include('project_main_copi_nie') # Research-only
    end

    it 'does not duplicate fields for a form whose dbname equals its own name' do
      qcs = questionclasses('member')
      expect(qcs).to include('member_dni_nie_pas')
      expect(qcs).to eq(qcs.uniq)
    end
  end

  describe 'an unknown name' do
    it 'resolves to no fields rather than raising' do
      expect(CBGP::Dataset.fields_for('definitely_not_a_form')).to eq([])
    end
  end

  describe 'CBGP::Dataset.key_method_for_form' do
    before { CBGP::Dataset.class_variable_get(:@@primary_key_cache).clear }

    it 'finds the primary-id method for a shared dbname' do
      expect(CBGP::Dataset.key_method_for_form('project')).to eq('int_project_code')
    end
  end

  describe 'get_dbname_sections_query' do
    it 'rejects an unsafe name before building SPARQL' do
      expect { get_dbname_sections_query(dbname: 'project"} ; DROP', language: 'en') }
        .to raise_error(StandardError)
    end
  end
end
