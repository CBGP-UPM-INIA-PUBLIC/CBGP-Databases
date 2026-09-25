# frozen_string_literal: true

require 'json'

module McpTools
  module Core
    # MCP tool: the churn-safe mechanism for any semantic grouping the
    # ontology maintainers define (or haven't yet) - e.g. whether project
    # funding types split into "international" vs "national" isn't
    # hardcoded anywhere in this codebase, because the ontology doesn't
    # currently encode that grouping either. Rather than guess at a mapping
    # in Ruby (which would silently go stale the moment a non-programmer
    # edits the ontology), this queries the ontology's actual class
    # hierarchy directly, so any grouping that DOES get added becomes
    # answerable immediately with no code change.
    class OntologyRelationships
      NAME = 'ontology_relationships'

      DESCRIPTION = <<~DESCRIPTION
        Looks up one ontology class's direct parent(s) and children in the
        CBGP ontology's actual class hierarchy - e.g. call this with
        class_name "European" (a project_type value from list_form_facets)
        to see what it's grouped under, if anything.

        IMPORTANT: if the value you're looking up has no useful parent
        grouping (parents is empty, or only contains the field's own
        answer-block), that means the ontology genuinely does not define
        that distinction yet - it is not a tool failure, and you should not
        guess or invent a grouping yourself (e.g. do not assume which
        funding types count as "international" if the ontology doesn't say
        so). Tell the user the distinction isn't defined in the data rather
        than fabricating an answer.
      DESCRIPTION

      INPUT_SCHEMA = {
        type: 'object',
        properties: {
          class_name: {
            type: 'string',
            description: 'An ontology local name - a questionclass, or one of its controlled-vocabulary values (the "id" from list_form_facets)'
          }
        },
        required: ['class_name']
      }.freeze

      def self.call(arguments)
        result = get_class_relationships_query(class_name: arguments['class_name'])
        [{ type: 'text', text: result.to_json }]
      end
    end
  end
end
