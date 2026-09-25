# frozen_string_literal: true

# Regression coverage for a real bug found 2026-08-26 while migrating real
# personnel data onto Virtuoso: several SPARQL Update queries wrote
# provenance triples (dcterms:created/modified/type, prov:generatedAtTime,
# etc.) as bare triples sitting in INSERT DATA {} but OUTSIDE any GRAPH {}
# block - intentionally, to land them in "the default graph". GraphDB
# tolerated this; Virtuoso's INSERT DATA implementation rejects it outright
# ("Virtuoso 37000 Error SP031: ... No plain default graph specified in the
# preamble"), and SPARQL 1.1 doesn't provide a way to declare a default
# graph for INSERT DATA specifically (WITH/USING only apply to
# INSERT/DELETE ... WHERE).
#
# The fix moved every such triple inside the record's own named GRAPH block
# instead (see lib/queries.rb's write_dataset_to_db_query/
# delete_dataset_query doc comments for why that loses nothing - every
# reader already knows the specific graph URI in advance). This spec exists
# so a bare default-graph triple can't quietly creep back in later: it's a
# plain string-structure check, not a live Virtuoso round-trip (this suite
# stays offline/hermetic - see spec_helper.rb), but that's exactly the part
# a live round-trip can't check for you at review time.
RSpec.describe 'no bare default-graph triples in generated SPARQL Update text' do
  # True once every non-comment, non-PREFIX line inside `query` (from the
  # first "INSERT DATA {"/"DELETE DATA {" onward) is accounted for by
  # brace-depth tracking as being inside at least one GRAPH {...} block -
  # i.e. brace-depth never returns to exactly 1 (meaning "inside INSERT/
  # DELETE DATA {} but not yet inside any nested GRAPH {}") while a
  # triple-shaped line (one ending in " ." or " ;") is present.
  def every_triple_inside_a_graph_block?(query)
    depth = 0
    inside_insert_or_delete_data = false

    query.each_line do |line|
      stripped = line.strip
      next if stripped.empty? || stripped.start_with?('PREFIX')

      inside_insert_or_delete_data ||= stripped.match?(/\A(INSERT|DELETE)\s+DATA\s*\{/)
      next unless inside_insert_or_delete_data

      is_bare_triple_line = depth == 1 && stripped.match?(/[.;]\s*\z/) && !stripped.start_with?('GRAPH')
      return false if is_bare_triple_line

      depth += stripped.count('{') - stripped.count('}')
    end

    true
  end

  describe 'write_dataset_to_db_query' do
    it "wraps every provenance and field triple inside the record's own GRAPH block" do
      dataset = CBGP::Dataset.new(type: 'personnel_project')
      dataset.primary_id = 'abc-123'
      dataset.title = 'A Project'

      query = write_dataset_to_db_query(dataset: dataset, oldid: nil, form: 'personnel_project')

      expect(every_triple_inside_a_graph_block?(query)).to be(true)
    end
  end

  describe 'delete_dataset_query' do
    let(:old_graph_uri) { "#{BASE_URI}project/context/abc-123" }
    let(:prov_solution) do
      RDF::Query::Solution.new(
        created: RDF::Literal.new('2020-01-01T00:00:00Z', datatype: RDF::XSD.dateTime),
        modified: RDF::Literal.new('2024-06-15T10:00:00Z', datatype: RDF::XSD.dateTime)
      )
    end
    let(:constructed_triples) do
      RDF::Graph.new { |g| g << [RDF::URI('urn:x'), RDF::URI('urn:y'), RDF::Literal('z')] }
    end

    before do
      allow(DATABASE).to receive(:query)
        .with(a_string_matching(/SELECT \?created \?modified/))
        .and_return([prov_solution])
      allow(DATABASE).to receive(:query)
        .with(a_string_matching(/CONSTRUCT/), hash_including(headers: { 'Accept' => 'application/n-triples' }))
        .and_return(constructed_triples)
      allow(HISTORY_DATABASE_UPDATE).to receive(:insert_data)
      allow(DATABASE_UPDATE).to receive(:update)
    end

    it 'wraps the history snapshot metadata (prov:.../local:history-*) inside its own GRAPH block' do
      captured_query = nil
      allow(HISTORY_DATABASE_UPDATE).to receive(:update) { |query| captured_query = query }

      delete_dataset_query(oldid: old_graph_uri)

      expect(every_triple_inside_a_graph_block?(captured_query)).to be(true)
    end
  end
end
