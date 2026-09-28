# frozen_string_literal: true

# Covers the generic activity-trigger mechanism (2026-09-28): the ontology
# can declare, via local:has-triggers, that selecting a specific Answer or
# creating a new record of a specific form should fire a side effect (email
# today - see lib/triggers.rb's module doc comment for the full design).
#
# These specs split into two layers, deliberately:
#   1. The SPARQL/ontology-read layer (get_answer_triggers_query,
#      get_form_triggers_query, Triggers.triggers_for_answer/triggers_for_form)
#      - exercised against REAL ontology structure (reusing the existing
#        cbgp:consejo/cbgp:consejo_yes answer block, already used by
#        member_cbgp_center_board) with a SYNTHETIC has-triggers node added
#        just for the test and removed afterward. Deliberately NOT added to
#        the shared fixture file: no real "member_approved"-style field
#        exists in the ontology yet (this repo's deliverable is the
#        infrastructure only - see lib/triggers.rb), so fabricating one
#        there would be exactly the kind of ontology/fixture drift this
#        project has hit real bugs from before.
#   2. The transition-detection/dispatch logic (Triggers.check_and_fire,
#      Triggers.dispatch, EmailTrigger) - exercised with lightweight doubles
#      standing in for CBGP::Dataset, so these stay fast/isolated and don't
#      depend on exact real field shapes.
RSpec.describe 'activity-based triggers' do
  # --- Layer 1: SPARQL/ontology-read layer, against real ontology structure ---
  describe 'get_answer_triggers_query / Triggers.triggers_for_answer' do
    let(:trigger_node) { 'https://w3id.org/CBGP-App#__test_consejo_yes_trigger__' }
    let(:test_statements) do
      [
        RDF::Statement.new(RDF::URI('https://w3id.org/CBGP-App#consejo_yes'), RDF::URI('urn:local:has-triggers'),
                           RDF::URI(trigger_node)),
        RDF::Statement.new(RDF::URI(trigger_node), RDF::URI('urn:local:trigger-type'), RDF::Literal('email')),
        RDF::Statement.new(RDF::URI(trigger_node), RDF::URI('urn:local:trigger-recipient-key'),
                           RDF::Literal('test_recipient'))
      ]
    end

    before do
      CBGP::Triggers.clear_cache!
      test_statements.each { |s| $ontology << s }
    end

    after do
      test_statements.each { |s| $ontology.delete(s) }
      CBGP::Triggers.clear_cache!
    end

    it 'resolves a real Answer class tagged with local:has-triggers to its type/recipient-key' do
      triggers = CBGP::Triggers.triggers_for_answer('consejo_yes')
      expect(triggers).to eq([{ type: 'email', params: { recipient_key: 'test_recipient' } }])
    end

    it 'returns an empty array for an Answer with no local:has-triggers at all' do
      expect(CBGP::Triggers.triggers_for_answer('consejo_no')).to eq([])
    end

    it 'returns an empty array (fails open) for a nonexistent/invalid answer fragment, never raises' do
      expect { CBGP::Triggers.triggers_for_answer('not a real fragment !!') }.not_to raise_error
      expect(CBGP::Triggers.triggers_for_answer('not a real fragment !!')).to eq([])
    end

    it 'caches lookups, and clear_cache! actually clears both caches' do
      first = CBGP::Triggers.triggers_for_answer('consejo_yes')
      test_statements.each { |s| $ontology.delete(s) } # mutate the ontology without clearing the cache
      expect(CBGP::Triggers.triggers_for_answer('consejo_yes')).to eq(first) # still served from cache

      CBGP::Triggers.clear_cache!
      expect(CBGP::Triggers.triggers_for_answer('consejo_yes')).to eq([]) # re-queried, node is gone
    end
  end

  describe 'get_form_triggers_query / Triggers.triggers_for_form' do
    # 'member' is deliberately NOT used as the synthetic-injection subject
    # here: it now carries REAL local:has-triggers data in production (see
    # the dedicated 'real production ontology data' example below), so
    # adding a second, synthetic trigger to it would make this test's
    # single-result assertion collide with genuine content. 'publication'
    # has no trigger config of its own (confirmed by the sibling "empty"
    # test) and isn't expected to gain any incidentally.
    let(:trigger_node) { 'https://w3id.org/CBGP-App#__test_publication_submission_trigger__' }
    let(:test_statements) do
      [
        RDF::Statement.new(RDF::URI('https://w3id.org/CBGP-App#publication'), RDF::URI('urn:local:has-triggers'),
                           RDF::URI(trigger_node)),
        RDF::Statement.new(RDF::URI(trigger_node), RDF::URI('urn:local:trigger-type'), RDF::Literal('email')),
        RDF::Statement.new(RDF::URI(trigger_node), RDF::URI('urn:local:trigger-recipient-key'),
                           RDF::Literal('new_publication_reviewer'))
      ]
    end

    before do
      CBGP::Triggers.clear_cache!
      test_statements.each { |s| $ontology << s }
    end

    after do
      test_statements.each { |s| $ontology.delete(s) }
      CBGP::Triggers.clear_cache!
    end

    it 'resolves a form class tagged with local:has-triggers to its type/recipient-key' do
      triggers = CBGP::Triggers.triggers_for_form('publication')
      expect(triggers).to eq([{ type: 'email', params: { recipient_key: 'new_publication_reviewer' } }])
    end

    it 'returns an empty array for a form with no local:has-triggers configured' do
      expect(CBGP::Triggers.triggers_for_form('project')).to eq([])
    end
  end

  describe 'real production ontology data' do
    it "resolves member's real local:has-triggers (the new-hire form-level example wired up alongside this feature)" do
      triggers = CBGP::Triggers.triggers_for_form('member')
      expect(triggers).to eq([{ type: 'email', params: { recipient_key: 'new_member_reviewer' } }])
    end

    it "check_and_fire(check_form_level: false) does not fire member's real trigger even on a genuine creation - the admin route's actual call shape" do
      allow(CBGP::Triggers).to receive(:dispatch)
      dataset = double(CBGP::Dataset, form_type: 'member', primary_id: 'admin-created-1', old_values: nil, fields: [])

      CBGP::Triggers.check_and_fire(dataset: dataset, check_form_level: false)

      expect(CBGP::Triggers).not_to have_received(:dispatch)
    end
  end

  # --- Layer 2: transition detection / dispatch, with lightweight doubles ---
  describe '.check_and_fire' do
    let(:dataset) do
      double(
        CBGP::Dataset,
        form_type: 'member',
        primary_id: 'rec-1',
        old_values: old_values,
        fields: [
          { method: 'member_approved', questionclass: 'member_approved',
            answers: 'https://w3id.org/CBGP-App#member_approved' },
          { method: 'member_name', questionclass: 'member_name', answers: 'https://w3id.org/CBGP-App#FREE' }
        ]
      )
    end

    before do
      allow(dataset).to receive(:member_approved).and_return(new_approved_value)
      allow(dataset).to receive(:member_name).and_return('Maria')
      allow(CBGP::Triggers).to receive(:triggers_for_form).and_return([])
    end

    context 'when a field transitions into a trigger-tagged answer (old absent, new = trigger answer)' do
      let(:old_values) { { member_approved: nil } }
      let(:new_approved_value) { 'member_approved_yes' }

      it 'dispatches the trigger exactly once' do
        allow(CBGP::Triggers).to receive(:triggers_for_answer).with('member_approved_yes')
                                                              .and_return([{ type: 'email',
                                                                             params: { recipient_key: 'k' } }])
        allow(CBGP::Triggers).to receive(:dispatch)

        CBGP::Triggers.check_and_fire(dataset: dataset)

        expect(CBGP::Triggers).to have_received(:dispatch).once.with(type: 'email', params: { recipient_key: 'k' },
                                                                     dataset: dataset)
      end
    end

    context 'when the field is unchanged across the save (old == new == trigger answer)' do
      let(:old_values) { { member_approved: 'member_approved_yes' } }
      let(:new_approved_value) { 'member_approved_yes' }

      it 'does not fire again on an unrelated re-save' do
        allow(CBGP::Triggers).to receive(:triggers_for_answer).and_return([{ type: 'email', params: {} }])
        allow(CBGP::Triggers).to receive(:dispatch)

        CBGP::Triggers.check_and_fire(dataset: dataset)

        expect(CBGP::Triggers).not_to have_received(:dispatch)
      end
    end

    context 'when the field is toggled away from the trigger answer and back' do
      let(:old_values) { { member_approved: 'member_approved_no' } }
      let(:new_approved_value) { 'member_approved_yes' }

      it 'fires again (re-fire is the confirmed, intended semantics)' do
        allow(CBGP::Triggers).to receive(:triggers_for_answer).with('member_approved_yes')
                                                              .and_return([{ type: 'email', params: {} }])
        allow(CBGP::Triggers).to receive(:dispatch)

        CBGP::Triggers.check_and_fire(dataset: dataset)

        expect(CBGP::Triggers).to have_received(:dispatch).once
      end
    end

    context 'on a brand-new record (old_values is nil)' do
      let(:old_values) { nil }
      let(:new_approved_value) { 'member_approved_yes' }

      it 'still fires the answer-level trigger, treating it as a transition from absent' do
        allow(CBGP::Triggers).to receive(:triggers_for_answer).with('member_approved_yes')
                                                              .and_return([{ type: 'email', params: {} }])
        allow(CBGP::Triggers).to receive(:dispatch)

        CBGP::Triggers.check_and_fire(dataset: dataset)

        expect(CBGP::Triggers).to have_received(:dispatch).once
      end
    end

    context 'a #FREE-sentinel field' do
      let(:old_values) { { member_approved: nil } }
      let(:new_approved_value) { nil }

      it 'is skipped without attempting a trigger lookup for it' do
        allow(CBGP::Triggers).to receive(:triggers_for_answer)

        CBGP::Triggers.check_and_fire(dataset: dataset)

        expect(CBGP::Triggers).not_to have_received(:triggers_for_answer).with('Maria')
      end
    end

    context 'form-level triggers, on record creation' do
      let(:old_values) { nil }
      let(:new_approved_value) { nil }

      it 'dispatches a configured form-level trigger and does not call on_no_form_trigger' do
        allow(CBGP::Triggers).to receive(:triggers_for_form).with('member')
                                                            .and_return([{ type: 'email',
                                                                           params: { recipient_key: 'reviewer' } }])
        allow(CBGP::Triggers).to receive(:dispatch)
        fallback = spy('fallback')

        CBGP::Triggers.check_and_fire(dataset: dataset, on_no_form_trigger: -> { fallback.call })

        expect(CBGP::Triggers).to have_received(:dispatch).with(type: 'email', params: { recipient_key: 'reviewer' },
                                                                dataset: dataset)
        expect(fallback).not_to have_received(:call)
      end

      it 'calls on_no_form_trigger when no form-level config exists' do
        allow(CBGP::Triggers).to receive(:triggers_for_form).with('member').and_return([])
        fallback = spy('fallback')

        CBGP::Triggers.check_and_fire(dataset: dataset, on_no_form_trigger: -> { fallback.call })

        expect(fallback).to have_received(:call)
      end

      it 'does not raise when on_no_form_trigger is omitted' do
        allow(CBGP::Triggers).to receive(:triggers_for_form).with('member').and_return([])
        expect { CBGP::Triggers.check_and_fire(dataset: dataset) }.not_to raise_error
      end

      it 'never checks form-level triggers on an edit (old_values present)' do
        edit_double = double(
          CBGP::Dataset, form_type: 'member', primary_id: 'rec-1',
                         old_values: { member_approved: 'member_approved_yes' }, fields: []
        )
        allow(CBGP::Triggers).to receive(:triggers_for_form)

        CBGP::Triggers.check_and_fire(dataset: edit_double)

        expect(CBGP::Triggers).not_to have_received(:triggers_for_form)
      end

      # The admin route's actual call shape (check_form_level: false): the
      # admin UI can also create a brand-new record directly (GET
      # /cbgp/dataset/:database), which is a "creation" the same as a
      # User-facing submission - but the admin team shouldn't be notified
      # when THEY create a record, only when a User registers themselves.
      it 'does not check form-level triggers at all when check_form_level: false, even with real config present and even on a genuine creation' do
        allow(CBGP::Triggers).to receive(:triggers_for_form).with('member')
                                                            .and_return([{ type: 'email',
                                                                           params: { recipient_key: 'reviewer' } }])
        allow(CBGP::Triggers).to receive(:dispatch)
        fallback = spy('fallback') # even a fallback, if one were mistakenly passed, must not fire either

        CBGP::Triggers.check_and_fire(dataset: dataset, check_form_level: false, on_no_form_trigger: lambda {
          fallback.call
        })

        expect(CBGP::Triggers).not_to have_received(:triggers_for_form)
        expect(CBGP::Triggers).not_to have_received(:dispatch)
        expect(fallback).not_to have_received(:call)
      end
    end

    context 'a Multiple-cardinality field' do
      let(:old_values) { { member_publications: %w[pub_a pub_b] } }
      let(:new_approved_value) { nil }

      it 'fires only for the newly-added value, not pre-existing ones' do
        multi_field = { method: 'member_publications', questionclass: 'member_publications',
                        answers: 'https://w3id.org/CBGP-App#publications' }
        multi_dataset = double(
          CBGP::Dataset, form_type: 'member', primary_id: 'rec-1',
                         old_values: old_values, fields: [multi_field]
        )
        allow(multi_dataset).to receive(:member_publications).and_return(%w[pub_a pub_b pub_c])
        allow(CBGP::Triggers).to receive(:triggers_for_form).and_return([])
        allow(CBGP::Triggers).to receive(:triggers_for_answer).and_return([])
        allow(CBGP::Triggers).to receive(:dispatch)

        CBGP::Triggers.check_and_fire(dataset: multi_dataset)

        expect(CBGP::Triggers).to have_received(:triggers_for_answer).with('pub_c').once
        expect(CBGP::Triggers).not_to have_received(:triggers_for_answer).with('pub_a')
        expect(CBGP::Triggers).not_to have_received(:triggers_for_answer).with('pub_b')
      end
    end
  end

  describe '.dispatch' do
    it 'warns and does not raise for an unregistered trigger type' do
      dataset = double(form_type: 'member', primary_id: 'rec-1')
      expect { CBGP::Triggers.dispatch(type: 'not_a_real_type', params: {}, dataset: dataset) }.not_to raise_error
    end

    it "catches and logs a handler's failure rather than propagating it" do
      dataset = double(form_type: 'member', primary_id: 'rec-1')
      failing_handler = Class.new { def self.fire(params:, dataset:) = raise('boom') } # rubocop:disable Lint/UnusedMethodArgument
      CBGP::Triggers.register('__test_failing__', failing_handler)

      expect { CBGP::Triggers.dispatch(type: '__test_failing__', params: {}, dataset: dataset) }.not_to raise_error
    ensure
      CBGP::Triggers::REGISTRY.delete('__test_failing__')
    end
  end

  describe CBGP::EmailTrigger do
    let(:dataset) { double(form_type: 'member', primary_id: 'rec-1') }

    around do |example|
      original = TRIGGER_RECIPIENTS.dup
      TRIGGER_RECIPIENTS.clear
      TRIGGER_RECIPIENTS['aaron_key'] = 'aaron@example.org'
      example.run
      TRIGGER_RECIPIENTS.clear
      TRIGGER_RECIPIENTS.merge!(original)
    end

    it 'resolves the recipient key via TRIGGER_RECIPIENTS and sends through the shared mailer' do
      allow(MyHelpers).to receive(:_send_notification)

      described_class.fire(params: { recipient_key: 'aaron_key' }, dataset: dataset)

      expect(MyHelpers).to have_received(:_send_notification).with(
        to: 'aaron@example.org',
        subject: a_string_including('member', 'rec-1'),
        message: a_string_including('rec-1', APP_BASE_URL)
      )
    end

    it 'raises (caught by Triggers.dispatch, not swallowed here) for an unknown recipient key' do
      expect do
        described_class.fire(params: { recipient_key: 'nonexistent_key' }, dataset: dataset)
      end.to raise_error(KeyError)
    end
  end

  # --- End-to-end: a REAL CBGP::Dataset (not a double), a real ontology
  # field (member_cbgp_center_board, local:method "consejo", real
  # answer-block consejo/consejo_yes), and a synthetic has-triggers node -
  # closes the gap between the mocked unit tests above and an actual
  # Dataset's dynamically-defined per-instance accessor methods (see
  # lib/dataset_classes.rb), which a double can't verify against.
  describe 'end-to-end with a real CBGP::Dataset' do
    let(:trigger_node) { 'https://w3id.org/CBGP-App#__test_consejo_yes_trigger__' }
    let(:test_statements) do
      [
        RDF::Statement.new(RDF::URI('https://w3id.org/CBGP-App#consejo_yes'), RDF::URI('urn:local:has-triggers'),
                           RDF::URI(trigger_node)),
        RDF::Statement.new(RDF::URI(trigger_node), RDF::URI('urn:local:trigger-type'), RDF::Literal('email')),
        RDF::Statement.new(RDF::URI(trigger_node), RDF::URI('urn:local:trigger-recipient-key'),
                           RDF::Literal('e2e_recipient'))
      ]
    end

    before do
      CBGP::Triggers.clear_cache!
      test_statements.each { |s| $ontology << s }
    end

    after do
      test_statements.each { |s| $ontology.delete(s) }
      CBGP::Triggers.clear_cache!
    end

    it 'fires exactly once when a real field transitions into the tagged answer, and not on a later unrelated save' do
      allow(CBGP::Triggers).to receive(:triggers_for_form).and_return([])
      allow(CBGP::Triggers).to receive(:dispatch)

      dataset = CBGP::Dataset.new(type: 'member')
      dataset.primary_id = 'e2e-rec-1'
      dataset.consejo = 'consejo_yes' # local:method for member_cbgp_center_board
      # old_values is keyed by QUESTIONCLASS (member_cbgp_center_board), not
      # by local:method (consejo) - confirmed against the real write path's
      # shape (summarize_field_changes, lib/core.rb).
      dataset.old_values = { member_cbgp_center_board: nil } # was unset before this save - a real transition

      CBGP::Triggers.check_and_fire(dataset: dataset)

      expect(CBGP::Triggers).to have_received(:dispatch).once.with(
        type: 'email', params: { recipient_key: 'e2e_recipient' }, dataset: dataset
      )

      # A second save where the field is unchanged (already consejo_yes
      # before AND after) must not fire again.
      dataset.old_values = { member_cbgp_center_board: 'consejo_yes' }
      CBGP::Triggers.check_and_fire(dataset: dataset)

      expect(CBGP::Triggers).to have_received(:dispatch).once # still just the one call from above
    end
  end
end
