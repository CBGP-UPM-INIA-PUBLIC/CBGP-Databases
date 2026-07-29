# frozen_string_literal: true

# Covers the per-form pre-populated-answer mechanism: a form can assign a
# default value to one of its fields via the ontology's local:has-defaults
# branch, without that default living on the shared question class itself -
# necessary because the same question class can be reused across multiple
# forms, each wanting a different default.
#
# This mechanism's original live demonstration field, project_category (a
# hidden discriminator distinguishing Research vs Personnel Project
# records), was removed 2026-07-28 once that specific use case was
# superseded by a structural mechanism instead - every record on every form
# now automatically gets a dcterms:type stamp on its graph at save time (see
# write_dataset_to_db_query in lib/queries.rb and spec/lib/dcterms_type_spec.rb),
# with zero ontology configuration required, which is strictly more general
# than a hand-declared discriminator field only these two forms had.
#
# local:has-defaults itself is NOT going away - it's still the right tool
# for a real, human-meaningful field that needs a different default value
# per form. There is currently no live example of it in the ontology, so
# this spec exercises the query/method layer's behavior directly rather
# than against a real field - primarily the "no defaults declared anywhere"
# case, which is now universally true, and which must keep degrading
# gracefully (empty results, not an error) exactly like it always has for
# any form that never declared local:has-defaults.
RSpec.describe 'per-form default answers' do
  describe '#get_form_defaults_query / .form_default_answers' do
    it 'returns an empty hash for a form with no local:has-defaults at all' do
      expect(CBGP::Dataset.form_default_answers(form: 'project')).to eq({})
      expect(CBGP::Dataset.form_default_answers(form: 'personnel_project')).to eq({})
      expect(CBGP::Dataset.form_default_answers(form: 'member')).to eq({})
    end

    it 'returns an empty hash for a nonexistent form class rather than raising' do
      expect(CBGP::Dataset.form_default_answers(form: 'not_a_real_form')).to eq({})
    end
  end

  describe '.new_with_defaults' do
    it 'behaves exactly like plain .new for a form with no defaults declared at all' do
      with_defaults = CBGP::Dataset.new_with_defaults(type: 'member', form: 'member')
      plain = CBGP::Dataset.new(type: 'member')
      expect(with_defaults.fields).to eq(plain.fields)
    end

    it 'behaves exactly like plain .new for the project forms too (no defaults declared on either)' do
      %w[project personnel_project].each do |form|
        with_defaults = CBGP::Dataset.new_with_defaults(type: 'project', form: form)
        plain = CBGP::Dataset.new(type: 'project')
        expect(with_defaults.fields).to eq(plain.fields)
      end
    end
  end
end
