# frozen_string_literal: true

# ListFormFacets and OntologyRelationships (lib/mcp_tools/core/) only ever
# touch $ontology, not Virtuoso, so these run against the real (fixture-
# synced, see spec_helper) ontology data, no mocking needed - the same
# reasoning as the existing get_form_defaults_query/field_query specs.
RSpec.describe 'Core MCP discovery tools' do
  describe McpTools::Core::ListFormFacets do
    it 'lists member fields with their questionclass identifiers and, for a controlled-vocabulary field, its legal values' do
      response = described_class.call({ 'form_type' => 'member' })
      body = JSON.parse(response.first[:text])

      expect(body['form_type']).to eq('member')
      questionclasses = body['facets'].map { |f| f['questionclass'] }
      expect(questionclasses).to include('member_orcid')

      status_field = body['facets'].find { |f| f['questionclass'] == 'member_status' }
      expect(status_field['values']).to be_an(Array)
      expect(status_field['values'].first).to have_key('id')
      expect(status_field['values'].first).to have_key('label')
    end

    it 'returns an empty facets list for a nonexistent form_type, rather than raising (a SPARQL SELECT with no matches is not an error)' do
      response = described_class.call({ 'form_type' => 'not_a_real_form' })
      body = JSON.parse(response.first[:text])
      expect(body['facets']).to eq([])
    end
  end

  describe McpTools::Core::OntologyRelationships do
    it 'finds project-type as the parent of the "European" project_type value' do
      response = described_class.call({ 'class_name' => 'European' })
      body = JSON.parse(response.first[:text])

      parent_ids = body['parents'].map { |p| p['id'] }
      expect(parent_ids).to include('project-type')
    end

    it 'returns no parents for a class with no rdfs:subClassOf, without raising' do
      response = described_class.call({ 'class_name' => 'forms' })
      body = JSON.parse(response.first[:text])
      expect(body['parents']).to eq([])
    end

    it 'raises rather than interpolate an injected class_name unchecked' do
      expect do
        described_class.call({ 'class_name' => 'x } DROP ALL #' })
      end.to raise_error(ArgumentError)
    end
  end
end
