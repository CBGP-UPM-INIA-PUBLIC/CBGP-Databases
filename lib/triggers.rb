# frozen_string_literal: true

# Generic activity-based triggers: the ontology can declare, via
# local:has-triggers, that either (a) selecting a specific Answer, or (b)
# creating a new record of a specific form, should fire a side effect (an
# email today; other trigger TYPES can be added later by registering a new
# handler class - see REGISTRY below - with no change to detection/dispatch).
#
# Both kinds of event reuse the identical reified-node vocabulary
# (local:trigger-type, local:trigger-recipient-key - see
# get_answer_triggers_query/get_form_triggers_query in lib/queries.rb) and
# the identical dispatch mechanism; only the SPARQL subject differs (an
# Answer class vs a form class).
#
# "Fires once" needs no persisted "already fired" flag anywhere: it's
# derived fresh, at save time, from comparing a record's own field values
# immediately before vs. after THIS save (dataset.old_values, surfaced by
# write_dataset_to_db_query in lib/queries.rb) - an answer transition and a
# record's creation are each inherently one-time events per save, so the
# diff itself is the dedupe mechanism. A field later toggled away from a
# trigger answer and back WILL fire again - that's a deliberate choice
# (confirmed with the user), not an oversight.
#
# Dispatch only ever happens from the two route handlers in
# app/controllers/routes.rb, never from the shared write path
# (write_dataset_to_db/write_dataset_to_db_query) - lib/loaders.rb's bulk
# import path calls into that same low-level write path without going
# through a route, and must never fire real trigger emails during a bulk
# historical load.
module CBGP
  module Triggers
    @@answer_triggers_cache = {}
    @@form_triggers_cache = {}

    def self.clear_cache!
      @@answer_triggers_cache.clear
      @@form_triggers_cache.clear
    end

    def self.triggers_for_answer(answer_fragment)
      @@answer_triggers_cache[answer_fragment] ||= fetch_triggers do
        get_answer_triggers_query(answer_class: answer_fragment)
      end
    end

    def self.triggers_for_form(form_class)
      @@form_triggers_cache[form_class] ||= fetch_triggers { get_form_triggers_query(form_class: form_class) }
    end

    def self.fetch_triggers
      # get_answer_triggers_query/get_form_triggers_query already execute
      # against $ontology and return solutions (this codebase's "get_X_query"
      # naming is a carryover - see get_form_formulas_query et al.), so this
      # yields directly to one of those, no re-parsing.
      results = yield
      results.map { |row| { type: row[:type].to_s, params: { recipient_key: row[:recipient_key]&.to_s } } }
    rescue StandardError
      [] # unknown/invalid class, or malformed ontology data - fail open, never block a save
    end
    private_class_method :fetch_triggers

    # rubocop:disable Style/MutableConstant -- .register mutates this in
    # place (see the call at the bottom of this file, and any future
    # trigger-type file); freezing it would break registration entirely.
    REGISTRY = {}
    # rubocop:enable Style/MutableConstant

    def self.register(type, handler)
      REGISTRY[type.to_s] = handler
    end

    # Fire-and-forget, matching notify_new_user_submission's own precedent
    # (lib/helpers.rb) - a bad config or downstream failure is logged,
    # never raised, never blocks the save that already succeeded.
    def self.dispatch(type:, params:, dataset:)
      handler = REGISTRY[type.to_s]
      return warn("[TRIGGERS] unknown trigger type #{type.inspect}") unless handler

      handler.fire(params: params, dataset: dataset)
    rescue StandardError => e
      warn "[TRIGGERS] #{type} trigger failed for #{dataset.form_type}/#{dataset.primary_id}: #{e.class}: #{e.message}"
    end

    # Called once per successful save from a route handler (never from the
    # shared write path - see module doc comment above).
    #
    # @param dataset [CBGP::Dataset] the just-written dataset
    # @param on_no_form_trigger [Proc, nil] invoked (only on a creation) if
    #   no ontology form-level trigger is configured for this form - lets a
    #   specific route preserve an existing default (see the user-facing
    #   route's use of notify_new_user_submission as this fallback) without
    #   that default silently applying to routes that never asked for it.
    # @param check_form_level [Boolean] whether to check form-level ("on
    #   creation") triggers at all. There is only ONE ontology form class
    #   per dbname (e.g. cbgp:member) shared by both the admin and
    #   User-facing routes - the admin UI can create a brand-new record
    #   directly too (GET /cbgp/dataset/:database), which is also a
    #   "creation" as far as dataset.old_values is concerned. A form-level
    #   trigger is meant for "a User registered themselves," not "an admin
    #   created a record," so the admin route passes false here - this
    #   restores the exact asymmetry the old hardcoded
    #   notify_new_user_submission already had (only ever called from the
    #   User-facing route). Answer-level (transition) triggers below are
    #   NOT gated by this - those are legitimately meant to fire from admin
    #   edits too (e.g. Damaris approving a record).
    def self.check_and_fire(dataset:, on_no_form_trigger: nil, check_form_level: true)
      if check_form_level && dataset.old_values.nil? # this save created the record
        form_triggers = triggers_for_form(dataset.form_type)
        form_triggers.each { |t| dispatch(type: t[:type], params: t[:params], dataset: dataset) }
        on_no_form_trigger&.call if form_triggers.empty?
      end

      dataset.fields.each do |field|
        next unless field[:answers] && !field[:answers].to_s.end_with?('#FREE')

        new_values = Array(dataset.public_send(field[:method]))
        old_values = dataset.old_values ? Array(dataset.old_values[field[:questionclass].to_sym]) : []

        (new_values - old_values).each do |answer_fragment|
          triggers_for_answer(answer_fragment).each do |t|
            dispatch(type: t[:type], params: t[:params], dataset: dataset)
          end
        end
      end
    end
  end

  class EmailTrigger
    def self.fire(params:, dataset:)
      recipient = TRIGGER_RECIPIENTS.fetch(params[:recipient_key])
      subject = "[CBGP] Action needed: #{dataset.form_type} #{dataset.primary_id}"
      link = "#{APP_BASE_URL}/cbgp/dataset/#{dataset.form_type}/#{dataset.primary_id}"
      body = "Record #{dataset.primary_id} (#{dataset.form_type}) just transitioned into a state requiring action.\n" \
             "Open: #{link}"
      MyHelpers._send_notification(to: recipient, subject: subject, message: body)
    end
  end
  Triggers.register('email', EmailTrigger)
end
