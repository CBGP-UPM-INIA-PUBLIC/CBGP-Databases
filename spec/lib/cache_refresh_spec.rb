# frozen_string_literal: true

# Covers the GET /cbgp/refresh gap fixed 2026-07-06: reloading $ontology on
# its own does not invalidate CBGP::Dataset's or Questionnaire's per-form-type
# caches, so a refresh used to keep serving stale field definitions (e.g. a
# newly-added currency field wouldn't show up) until the whole app process
# restarted.
RSpec.describe 'ontology cache invalidation' do
  describe 'CBGP::Dataset.clear_caches!' do
    it 'forces fields_for to rebuild its result instead of returning the cached array' do
      first = CBGP::Dataset.fields_for('project')
      CBGP::Dataset.clear_caches!
      second = CBGP::Dataset.fields_for('project')

      expect(second).to eq(first) # same ontology, so same content...
      expect(second).not_to equal(first) # ...but a genuinely rebuilt object, not the stale cached one
    end
  end

  describe 'Questionnaire.clear_cache!' do
    it 'forces get_cached to rebuild its result instead of returning the cached object' do
      first = Questionnaire.get_cached(questionnaire_type: 'project')
      Questionnaire.clear_cache!
      second = Questionnaire.get_cached(questionnaire_type: 'project')

      expect(second).not_to equal(first)
    end
  end
end
