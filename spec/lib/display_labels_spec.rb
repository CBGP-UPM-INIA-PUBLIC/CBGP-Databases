# frozen_string_literal: true

# Covers the search-results display bug fixed 2026-07-06: controlled-
# vocabulary fields (select/radio/tree-selector) store an ontology class ID
# (e.g. "Awarded"), and the results table/TSV export used to print that
# raw ID instead of resolving it to the current-language rdfs:label (e.g.
# "Awarded" / "Concedido").
RSpec.describe 'controlled-vocabulary display resolution' do
  # project_status is a real controlled-vocabulary field in the fixture
  # ontology (answers block "project-status", not FREE/NUM/DATE/HIDDEN) whose
  # English and Spanish labels differ. (project_type, used here before, was
  # removed from the project forms 2026-10-06.)
  let(:controlled_field) { CBGP::Dataset.fields_for('userproject').find { |f| f[:questionclass] == 'project_status' } }
  let(:free_text_field) { CBGP::Dataset.fields_for('userproject').find { |f| f[:questionclass] == 'project_title' } }
  let(:currency_field) { CBGP::Dataset.fields_for('userproject').find { |f| f[:questionclass] == 'personnel_project_total_funding' } }

  before do
    raise "fixture ontology no longer has 'project_status' - update this spec" unless controlled_field
  end

  describe '#controlled_vocabulary_field?' do
    it 'is true for a select/radio/tree-selector-backed field' do
      expect(controlled_vocabulary_field?(controlled_field)).to be true
    end

    it 'is false for free text, date, and number fields (FREE/DATE/NUM/HIDDEN answer blocks)' do
      expect(controlled_vocabulary_field?(free_text_field)).to be false
    end
  end

  describe '#resolve_display_value' do
    it 'resolves a controlled-vocabulary class ID to its English label' do
      Thread.current[:language] = 'en'
      expect(resolve_display_value(controlled_field, 'Awarded')).to eq('Awarded')
    end

    it 'resolves the same class ID to its Spanish label' do
      Thread.current[:language] = 'es'
      expect(resolve_display_value(controlled_field, 'Awarded')).to eq('Concedido')
    end

    it 'falls back to the raw ID if no label is found, so data never disappears' do
      expect(resolve_display_value(controlled_field, 'not-a-real-class')).to eq('not-a-real-class')
    end

    it 'passes free text through unchanged' do
      expect(resolve_display_value(free_text_field, 'My Innovative Project')).to eq('My Innovative Project')
    end

    it 'still formats currency fields via format_currency, not label lookup' do
      expect(resolve_display_value(currency_field, '15000.50')).to eq(format_currency('15000.50'))
    end
  end

  describe '#cached_label_for_id' do
    it 'returns the same result as get_label_for_id directly' do
      expect(cached_label_for_id(id: 'Awarded', language: 'en'))
        .to eq(get_label_for_id(id: 'Awarded', language: 'en'))
    end

    it 'caches per (id, language) so the two languages do not clobber each other' do
      en_label = cached_label_for_id(id: 'Awarded', language: 'en')
      es_label = cached_label_for_id(id: 'Awarded', language: 'es')
      expect(en_label).to eq('Awarded')
      expect(es_label).to eq('Concedido')
    end
  end
end
