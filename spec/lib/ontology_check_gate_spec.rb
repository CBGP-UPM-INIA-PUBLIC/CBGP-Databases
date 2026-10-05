# frozen_string_literal: true

# The ontology's clerical checks (untagged labels, missing en/es labels, forms
# that would never be listed, ...) live WITH the ontology, in
# CBGP-Ontology/check_ontology.rb, so whoever edits the ontology can run them
# before pushing (see that repo's README). This is only the gate: the ontology
# file this suite is running against must have no errors, so a slip fails the
# build with the class named instead of surfacing later as something silently
# missing from a menu.
#
# Skipped (loudly, with the reason) when there is no sibling CBGP-Ontology
# checkout to take the checker from, or the ontology under test is not a
# local file (the live-URL tier of spec_helper's ontology resolution).
RSpec.describe 'ontology clerical check (CBGP-Ontology/check_ontology.rb)' do
  CHECKER_PATH = File.expand_path('../../../CBGP-Ontology/check_ontology.rb', __dir__)

  it 'finds no errors in the ontology file under test' do
    skip "no sibling CBGP-Ontology checkout, so no checker to run (#{CHECKER_PATH})" unless File.file?(CHECKER_PATH)
    path = ENV['CBGP_KB'].to_s
    skip "the ontology under test is not a local file (#{path.inspect})" unless File.file?(path)

    load CHECKER_PATH # defines OntologyCheck; does not run the command line (guarded by $PROGRAM_NAME)
    errors = OntologyCheck.errors(OntologyCheck.check_file(path))
    lines = OntologyCheck.line_numbers(path)

    report = errors.first(25).map { |f| "  line #{lines[f.subject] || '?'}: #{f}" }.join("\n")
    expect(errors).to be_empty, "the ontology has #{errors.size} error(s) to fix at source " \
                                "(cd CBGP-Ontology && ruby check_ontology.rb for the full report):\n#{report}"
  end

  it 'would catch the original bug (a form category written without a language tag)' do
    skip 'no sibling CBGP-Ontology checkout' unless File.file?(CHECKER_PATH)
    load CHECKER_PATH
    xml = <<~XML
      <rdf:RDF xmlns:owl="http://www.w3.org/2002/07/owl#" xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
               xmlns:rdfs="http://www.w3.org/2000/01/rdf-schema#" xmlns:local="urn:local:">
        <owl:Class rdf:about="https://w3id.org/CBGP-App#european_research_project">
          <rdfs:subClassOf rdf:resource="https://w3id.org/CBGP-App#forms"/>
          <rdfs:label xml:lang="en">European</rdfs:label><rdfs:label xml:lang="es">Europeo</rdfs:label>
          <local:dbname xml:lang="en">project</local:dbname>
          <local:form-category>Core</local:form-category>
          <local:has-fields rdf:resource="https://w3id.org/CBGP-App#x"/>
        </owl:Class>
      </rdf:RDF>
    XML
    errors = OntologyCheck.errors(OntologyCheck.check_xml(xml))
    expect(errors.map(&:code)).to eq([:untagged_annotation])
    expect(errors.first.subject).to eq('european_research_project')
  end
end
