# frozen_string_literal: true

require_relative '../records'

module Mcp
  module Tools
    class GetRecord < Mcp::Tool
      tool_name 'get_record'
      title "Get one record"
      summary "Read one record in full by form and id, with cross-references resolved to readable labels."
      description <<~TEXT
        form and id come from search_records or linked_records. "references" gives, for each field that holds another
        record's key (a project's PI is stored as a DNI), that record's form, id and label. found:false = no record
        holds that key: say the key is unknown; never invent a name.

        Example: get_record {"form":"member","id":"34c37c2f-e6ec-49ca-97d7-aab18e432f9a"}
      TEXT
      param :form, type: 'string', required: true, description: 'Form name'
      param :id, type: 'string', required: true, description: 'The record id (a UUID) returned by search_records or linked_records. Never a name or a DNI.'

      def self.run(args)
        ctx = Records::Context.new
        form = ctx.form!(args['form'])
        graph = ctx.graph_uri(form, args['id'])
        record = ctx.build_records(form, [graph]).first
        raise ToolError, "No #{form.name} record with id '#{args['id']}'. Get ids from search_records, not from other fields." unless record

        refs = ctx.references_for(form, record)
        record[:references] = refs unless refs.empty?
        record
      end
    end
  end
end
