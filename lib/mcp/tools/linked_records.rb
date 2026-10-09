# frozen_string_literal: true

require_relative '../records'

module Mcp
  module Tools
    class LinkedRecords < Mcp::Tool
      DEFAULT_LIMIT = 50

      tool_name 'linked_records'
      title "Linked records"
      summary "Follow relationships from one record: what it points to, and which other forms' records point to it."
      description <<~TEXT
        outbound = records this one points to (its PI, its project). inbound = records in other forms that point to this
        one (a person's projects, funding commitments, publications; a project's commitments). Each group names the
        linking field (relation, relation_label), what its records are (record_kinds) and lists full records with their dates, ready to order in time.
        A person moving between projects has several commitment records: list them all, never merge them.
        skipped explains a link that could not be followed (e.g. the record has no ORCiD).
        Then use get_record or record_history on any record, or render_timeline on the dates.

        Example: linked_records {"form":"member","id":"34c37c2f-e6ec-49ca-97d7-aab18e432f9a"}
      TEXT
      param :form, type: 'string', required: true, description: 'Form name of the record'
      param :id, type: 'string', required: true, description: 'The record id (a UUID) returned by search_records or linked_records. Never a name or a DNI.'
      param :direction, type: 'string', enum: %w[both inbound outbound], description: 'Default "both"'
      param :limit_per_relation, type: 'integer', description: "Max records per relationship (default #{DEFAULT_LIMIT})"

      def self.run(args)
        ctx = Records::Context.new
        form = ctx.form!(args['form'])
        record = ctx.build_records(form, [ctx.graph_uri(form, args['id'])]).first
        raise ToolError, "No #{form.name} record with id '#{args['id']}'. Get ids from search_records." unless record

        direction = (args['direction'] || 'both').to_s
        limit = (args['limit_per_relation'] || DEFAULT_LIMIT).to_i.clamp(1, 200)
        skipped = []
        out = { record: record.slice(:form, :id, :label) }
        out[:outbound] = outbound(ctx, form, record) if %w[both outbound].include?(direction)
        out[:inbound] = inbound(ctx, form, record, limit, skipped) if %w[both inbound].include?(direction)
        out[:skipped] = skipped unless skipped.empty?
        out
      end

      # The records this one points to: one group per reference field.
      def self.outbound(ctx, form, record)
        fields = ctx.fields(form.name).select { |f| Records.reference_field?(f) }
        fields.filter_map do |f|
          values = Array(record[:fields][f[:questionclass]])
          next if values.empty?

          { relation: f[:questionclass], relation_label: f[:label],
            records: values.map do |v|
              ref = ctx.resolve_reference(f, v)
              ref || { key: v, found: false, note: "no #{f[:references_target]} record has this key" }
            end }
        end
      end

      # The records in other forms whose reference fields hold THIS record's
      # key: one group per (form storage, field).
      def self.inbound(ctx, form, record, limit, skipped)
        ctx.inbound_references(form.storage).filter_map do |ref|
          field = ref[:field]
          via = Records.fragment(field[:references_via])
          key = Array(record[:fields][via]).first
          if Records.blank_value?(key)
            skipped << { relation: field[:questionclass], reason: "this record has no value for #{via}, which #{ref[:form].name} records use to point at it" }
            next
          end

          graphs = execute_search(dataset_type: ref[:form].storage,
                                  search_params: { field[:questionclass] => key, "#{field[:questionclass]}__exact" => '1' }).uniq.sort
          next if graphs.empty?

          records = ctx.build_records(ref[:form], graphs.first(limit))
          group = { relation: field[:questionclass], relation_label: field[:label], total: graphs.size,
                    record_kinds: kinds(ctx, records), records: records }
          group[:truncated] = true if graphs.size > limit
          group
        end
      end

      # What the records of a group ARE, in words ("Funding Commitment"): the
      # relation label names the linking field ("Member (DNI)"), which makes a
      # poor heading. Distinct, since forms that share a storage mix in one group.
      def self.kinds(ctx, records)
        labels = ctx.forms.to_h { |f| [f.name, f.label] }
        records.map { |r| labels[r[:form]] || r[:form] }.uniq
      end
    end
  end
end
