# frozen_string_literal: true

require 'json'

module McpTools
  module Core
    # MCP tool: the discovery entry point for the core database. Same logic
    # as the existing GET /cbgp/facets/:form_type route (CBGP::Dataset.fields_for
    # + get_answer_block_query), exposed as a tool rather than only an HTTP
    # route so an agent can call it directly.
    #
    # Call this BEFORE search_records/get_record/aggregate/etc. - it's the
    # only way to learn which questionclass identifiers are legal for a
    # given form_type (they're required, exact-match arguments to every
    # other tool here and on the History server) and, for controlled-
    # vocabulary fields, which values are legal.
    class ListFormFacets
      NAME = 'list_form_facets'

      DESCRIPTION = <<~DESCRIPTION
        Lists every field (questionclass) on a form_type, e.g. "member",
        "project", "publication" - call this FIRST, before search_records,
        get_record, aggregate, or any History-server tool, to learn the
        exact questionclass identifiers those tools require (they do not
        accept human-readable labels, only these).

        For controlled-vocabulary fields (a fixed dropdown/radio list, not
        free text), also returns every legal value as {id, label} - id is
        what you pass as the value when searching or filtering on that
        field; label is what a human would read.
      DESCRIPTION

      INPUT_SCHEMA = {
        type: 'object',
        properties: {
          form_type: { type: 'string', description: 'e.g. "member", "project", "publication"' }
        },
        required: ['form_type']
      }.freeze

      def self.call(arguments)
        form_type = arguments['form_type']
        fields = CBGP::Dataset.fields_for(form_type)

        facets = fields.map { |f| facet_entry(f) }

        [{ type: 'text', text: { form_type: form_type, facets: facets }.to_json }]
      end

      def self.facet_entry(field)
        entry = {
          questionclass: field[:questionclass],
          label: field[:label],
          class: field[:class],
          cardinality: field[:cardinality],
          widget: field[:widget]
        }
        entry[:values] = controlled_vocabulary_values(field) if controlled_vocabulary_field?(field)
        entry
      end
      private_class_method :facet_entry

      def self.controlled_vocabulary_values(field)
        ablockid = field[:answers].to_s.split('#').last
        get_answer_block_query(ablockid: ablockid).map do |r|
          { id: r[:aid].to_s.split('#').last, label: r[:label].to_s }
        end
      end
      private_class_method :controlled_vocabulary_values
    end
  end
end
