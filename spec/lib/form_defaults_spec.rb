# frozen_string_literal: true

# Covers the per-form pre-populated-answer mechanism (2026-07-28): a form can
# assign a default value to one of its fields via the ontology's
# local:has-defaults branch, without that default living on the shared
# question class itself - necessary because the same question class can be
# reused across multiple forms (e.g. project_category, shared by the
# Research Project and Personnel Project forms), each wanting a different
# default.
#
# Exercised against the real `project_category` hidden discriminator field -
# the actual motivating use case for this mechanism - rather than a
# synthetic field, so this fails loudly if that ontology shape ever drifts.
RSpec.describe 'per-form default answers' do
  before do
    field = CBGP::Dataset.fields_for('project').find { |f| f[:questionclass] == 'project_category' }
    raise "fixture ontology no longer has 'project_category' - update this spec" unless field
  end

  describe '#get_form_defaults_query / .form_default_answers' do
    it 'resolves the Research form to its category default' do
      expect(CBGP::Dataset.form_default_answers(form: 'project')).to eq('project_category' => 'research-project')
    end

    it 'resolves the Personnel form to a different default for the same shared field' do
      defaults = CBGP::Dataset.form_default_answers(form: 'personnel_project')
      expect(defaults).to eq('project_category' => 'personnel-project')
    end

    it 'returns an empty hash for a form with no local:has-defaults at all' do
      expect(CBGP::Dataset.form_default_answers(form: 'member')).to eq({})
    end

    it 'returns an empty hash for a nonexistent form class rather than raising' do
      expect(CBGP::Dataset.form_default_answers(form: 'not_a_real_form')).to eq({})
    end
  end

  describe '.new_with_defaults' do
    it 'pre-populates the hidden field with the Research form default' do
      dataset = CBGP::Dataset.new_with_defaults(type: 'project', form: 'project')
      expect(dataset.category).to eq('research-project')
    end

    it 'pre-populates the same shared field with a different value on the Personnel form' do
      dataset = CBGP::Dataset.new_with_defaults(type: 'project', form: 'personnel_project')
      expect(dataset.category).to eq('personnel-project')
    end

    it 'the stored value resolves to a proper multilingual label, like any other controlled-vocabulary field' do
      dataset = CBGP::Dataset.new_with_defaults(type: 'project', form: 'personnel_project')
      field = dataset.fields.find { |f| f[:questionclass] == 'project_category' }
      expect(resolve_display_value(field, dataset.category)).to eq('Personnel Project')
    end

    it 'leaves fields with no declared default untouched (nil/blank, same as plain .new)' do
      dataset = CBGP::Dataset.new_with_defaults(type: 'project', form: 'project')
      expect(dataset.title).to be_nil
    end

    it 'behaves exactly like plain .new for a form with no defaults declared at all' do
      with_defaults = CBGP::Dataset.new_with_defaults(type: 'member', form: 'member')
      plain = CBGP::Dataset.new(type: 'member')
      expect(with_defaults.fields).to eq(plain.fields)
    end
  end
end
