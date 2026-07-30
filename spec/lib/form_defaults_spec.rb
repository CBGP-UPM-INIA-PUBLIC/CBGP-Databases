# frozen_string_literal: true

# Covers the per-form pre-populated-answer mechanism: a form can assign a
# default value to one of its fields via the ontology's local:has-defaults
# branch, without that default living on the shared question class itself -
# necessary because the same question class can be reused across multiple
# forms, each wanting a different default.
#
# This mechanism's ORIGINAL live demonstration field, project_category (a
# hidden discriminator distinguishing Research vs Personnel Project
# records), was removed 2026-07-28 once that specific use case was
# superseded by a structural mechanism instead - every record on every form
# now automatically gets a dcterms:type stamp on its graph at save time (see
# write_dataset_to_db_query in lib/queries.rb and spec/lib/dcterms_type_spec.rb),
# with zero ontology configuration required, which is strictly more general
# than a hand-declared discriminator field only these two forms had.
#
# local:has-defaults itself was never going away - it's still the right
# tool for a real, human-meaningful field that needs a different default
# value per form. What WAS missing, for a while, was any live example of it
# in the ontology at all - flagged as confusing by the user (2026-07-29):
# the Data Model docs page explained the mechanism but had nothing to point
# at. project_test_default_field (a plain, VISIBLE field - deliberately not
# hidden this time, so it's obvious at a glance which form produced which
# default) exists purely to fix that: a disposable, clearly-marked sandbox
# example, same spirit as the project_test_* chain already used to
# demonstrate local:has-formulas.
RSpec.describe 'per-form default answers' do
  before do
    field = CBGP::Dataset.fields_for('project').find { |f| f[:questionclass] == 'project_test_default_field' }
    raise "fixture ontology no longer has 'project_test_default_field' - update this spec" unless field
  end

  describe '#get_form_defaults_query / .form_default_answers' do
    # `include`, not `eq`: both project forms also carry the has-formulas
    # sandbox chain and their own real defaults are irrelevant here - this
    # spec only needs to prove the demo field resolves correctly per form.
    it 'resolves the Research form to its own default text' do
      defaults = CBGP::Dataset.form_default_answers(form: 'project')
      expect(defaults).to include('project_test_default_field' => 'This defaulted from the Research Project form')
    end

    it 'resolves the Personnel form to different default text for the same shared field' do
      defaults = CBGP::Dataset.form_default_answers(form: 'personnel_project')
      expect(defaults).to include('project_test_default_field' => 'This defaulted from the Personnel Project form')
    end

    it 'returns an empty hash for a form with no local:has-defaults at all' do
      expect(CBGP::Dataset.form_default_answers(form: 'member')).to eq({})
    end

    it 'returns an empty hash for a nonexistent form class rather than raising' do
      expect(CBGP::Dataset.form_default_answers(form: 'not_a_real_form')).to eq({})
    end
  end

  describe '.new_with_defaults' do
    it 'pre-populates the field with the Research form default' do
      dataset = CBGP::Dataset.new_with_defaults(type: 'project', form: 'project')
      expect(dataset.test_default_field).to eq('This defaulted from the Research Project form')
    end

    it 'pre-populates the same shared field with different text on the Personnel form' do
      dataset = CBGP::Dataset.new_with_defaults(type: 'project', form: 'personnel_project')
      expect(dataset.test_default_field).to eq('This defaulted from the Personnel Project form')
    end

    it 'behaves exactly like plain .new for a form with no defaults declared at all' do
      with_defaults = CBGP::Dataset.new_with_defaults(type: 'member', form: 'member')
      plain = CBGP::Dataset.new(type: 'member')
      expect(with_defaults.fields).to eq(plain.fields)
    end
  end
end
