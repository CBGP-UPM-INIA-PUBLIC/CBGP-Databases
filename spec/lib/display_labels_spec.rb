# frozen_string_literal: true

# Covers the search-results display bug fixed 2026-07-06: controlled-
# vocabulary fields (select/radio/tree-selector) store an ontology class ID
# (e.g. "Articulo-60"), and the results table/TSV export used to print that
# raw ID instead of resolving it to the current-language rdfs:label (e.g.
# "Article 60" / "Artículo-60").
RSpec.describe 'controlled-vocabulary display resolution' do
  # project_type is a real controlled-vocabulary field in the fixture
  # ontology (answers block "project-type", not FREE/NUM/DATE/HIDDEN).
  # Sara's 2026-08 project-fields restructuring split the old shared
  # "project" form into per-funding-type forms (european_research_project,
  # national_regional_research_project, private_research_project,
  # personnel_project) plus a separate "userproject" (user-facing) form -
  # project_type itself is unused/deprecated on the Core forms now (see its
  # ontology comment) but survives as a userproject field, so that's used as
  # the example here instead.
  let(:controlled_field) { CBGP::Dataset.fields_for('userproject').find { |f| f[:questionclass] == 'project_type' } }
  let(:free_text_field) { CBGP::Dataset.fields_for('userproject').find { |f| f[:questionclass] == 'project_title' } }
  let(:currency_field) { CBGP::Dataset.fields_for('userproject').find { |f| f[:questionclass] == 'personnel_project_total_funding' } }

  before do
    raise "fixture ontology no longer has 'project_type' - update this spec" unless controlled_field
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
      expect(resolve_display_value(controlled_field, 'Articulo-60')).to eq('Article 60')
    end

    it 'resolves the same class ID to its Spanish label' do
      Thread.current[:language] = 'es'
      expect(resolve_display_value(controlled_field, 'Articulo-60')).to eq('Artículo-60')
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
      expect(cached_label_for_id(id: 'Articulo-60', language: 'en'))
        .to eq(get_label_for_id(id: 'Articulo-60', language: 'en'))
    end

    it 'caches per (id, language) so the two languages do not clobber each other' do
      en_label = cached_label_for_id(id: 'Articulo-60', language: 'en')
      es_label = cached_label_for_id(id: 'Articulo-60', language: 'es')
      expect(en_label).to eq('Article 60')
      expect(es_label).to eq('Artículo-60')
    end
  end
end
