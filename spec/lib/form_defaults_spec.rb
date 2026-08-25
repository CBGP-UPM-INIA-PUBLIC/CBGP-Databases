# frozen_string_literal: true

# Covers the per-form pre-populated-answer mechanism: a form can assign a
# default value to one of its fields via the ontology's local:has-defaults
# branch, without that default living on the shared question class itself -
# necessary because the same question class can be reused across multiple
# forms, each wanting a different default.
#
# This mechanism's live demonstration field, project_test_default_field
# (added 2026-07-30 specifically so local:has-defaults had a real example
# to point at - see git history), was removed by Sara's 2026-08
# "clean test fields" ontology pass, and checked directly against the
# current ontology, NO form declares local:has-defaults at all anymore -
# a genuine, if harmless, coverage gap: the mechanism has zero live users
# right now.
#
# Rather than re-introduce a disposable sandbox field into the production
# ontology purely to keep this spec anchored to "real" content (which is
# exactly what kept breaking across Sara's last two restructuring passes),
# this spec now tests the mechanism at the same two layers form_formulas_spec
# does:
#   - the SPARQL query layer (#get_form_defaults_query/.form_default_answers)
#     is exercised against a small SYNTHETIC in-memory ontology (swapped into
#     $ontology for just this describe block, restored after) - this proves
#     the actual query construction/execution is correct, independent of
#     whatever the real ontology happens to declare today.
#   - .new_with_defaults (which also needs a real, renderable field to apply
#     the default onto) is exercised against real ontology content
#     (personnel_project's own project_title/project_affiliation fields),
#     with form_default_answers stubbed to supply the default value - since
#     there's no live default declared for either field, this isolates
#     "does applying a resolved default work correctly" from "does the
#     ontology currently declare one", the same split form_formulas_spec.rb
#     uses for its own query-layer vs. evaluation-layer coverage.
RSpec.describe 'per-form default answers' do
  describe '#get_form_defaults_query / .form_default_answers' do
    # A minimal synthetic ontology, swapped in for just these examples, so
    # this layer's correctness never depends on the real ontology declaring
    # any local:has-defaults at all (which, right now, it doesn't).
    around do |example|
      original_ontology = $ontology
      $ontology = RDF::Graph.new do |g|
        g << [RDF::URI('https://w3id.org/CBGP-App#spec_form_alpha'), RDF::URI('urn:local:has-defaults'), RDF::URI('https://w3id.org/CBGP-App#spec_default_alpha')]
        g << [RDF::URI('https://w3id.org/CBGP-App#spec_default_alpha'), RDF::URI('urn:local:default-for-field'), RDF::URI('https://w3id.org/CBGP-App#spec_shared_field')]
        g << [RDF::URI('https://w3id.org/CBGP-App#spec_default_alpha'), RDF::URI('urn:local:default-value'), RDF::Literal('Alpha default text')]
        g << [RDF::URI('https://w3id.org/CBGP-App#spec_form_beta'), RDF::URI('urn:local:has-defaults'), RDF::URI('https://w3id.org/CBGP-App#spec_default_beta')]
        g << [RDF::URI('https://w3id.org/CBGP-App#spec_default_beta'), RDF::URI('urn:local:default-for-field'), RDF::URI('https://w3id.org/CBGP-App#spec_shared_field')]
        g << [RDF::URI('https://w3id.org/CBGP-App#spec_default_beta'), RDF::URI('urn:local:default-value'), RDF::Literal('Beta default text')]
      end
      example.run
    ensure
      $ontology = original_ontology
    end

    it 'resolves one form to its own default text' do
      defaults = CBGP::Dataset.form_default_answers(form: 'spec_form_alpha')
      expect(defaults).to eq('spec_shared_field' => 'Alpha default text')
    end

    it 'resolves a different form to different default text for the same shared field' do
      defaults = CBGP::Dataset.form_default_answers(form: 'spec_form_beta')
      expect(defaults).to eq('spec_shared_field' => 'Beta default text')
    end

    it 'returns an empty hash for a form with no local:has-defaults at all' do
      expect(CBGP::Dataset.form_default_answers(form: 'spec_form_gamma')).to eq({})
    end

    it 'returns an empty hash for a nonexistent form class rather than raising' do
      expect(CBGP::Dataset.form_default_answers(form: 'not_a_real_form')).to eq({})
    end
  end

  describe '.new_with_defaults' do
    it 'pre-populates a real field with a resolved default value' do
      allow(CBGP::Dataset).to receive(:form_default_answers)
        .with(hash_including(form: 'personnel_project'))
        .and_return('project_title' => 'Defaulted title text')

      dataset = CBGP::Dataset.new_with_defaults(type: 'personnel_project', form: 'personnel_project')
      expect(dataset.title).to eq('Defaulted title text')
    end

    it 'pre-populates the same shared field with different text for a different form' do
      allow(CBGP::Dataset).to receive(:form_default_answers)
        .with(hash_including(form: 'european_research_project'))
        .and_return('project_title' => 'A different default')

      dataset = CBGP::Dataset.new_with_defaults(type: 'european_research_project', form: 'european_research_project')
      expect(dataset.title).to eq('A different default')
    end

    it 'behaves exactly like plain .new for a form with no defaults declared at all' do
      with_defaults = CBGP::Dataset.new_with_defaults(type: 'member', form: 'member')
      plain = CBGP::Dataset.new(type: 'member')
      expect(with_defaults.fields).to eq(plain.fields)
    end
  end
end
