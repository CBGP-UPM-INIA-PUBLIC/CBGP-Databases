# frozen_string_literal: true

require 'json'

module McpTools
  module Core
    # MCP tool: fetch one core-DB record by its primary_id (the value of
    # whichever field the ontology marks local:is-primary-id for that
    # form_type - e.g. an ORCID for a member, a DOI for a publication).
    class GetRecord
      NAME = 'get_record'

      DESCRIPTION = <<~DESCRIPTION
        Fetches one record from the core database by its primary_id - the
        record's natural identifier (e.g. a member's ORCID, a publication's
        DOI), not the @id graph URI search_records/get_record return.
        Raises a clear error if no record with that primary_id exists for
        that form_type.

        Returns the same compact-JSON-LD shape as search_records: an @id
        (pass this into the History-server tools to see this record's edit
        history) plus every field that has a value.
      DESCRIPTION

      INPUT_SCHEMA = {
        type: 'object',
        properties: {
          form_type: { type: 'string', description: 'e.g. "member", "project", "publication"' },
          primary_id: { type: 'string', description: "The record's natural identifier, e.g. an ORCID or DOI" }
        },
        required: %w[form_type primary_id]
      }.freeze

      def self.call(arguments)
        form_type = arguments['form_type']
        primary_id = arguments['primary_id']

        graph_row = retrieve_dataset_graph_query(primary_id: primary_id).first
        unless graph_row
          raise "No #{form_type} record found with primary_id #{primary_id.inspect}"
        end

        raw_record = fetch_datasets_raw_data(graph_uris: [graph_row[:g].to_s], database: form_type).first
        record = JsonldCompact.serialize_record(form_type: form_type, raw_record: raw_record)

        [{ type: 'text', text: record.to_json }]
      end
    end
  end
end
