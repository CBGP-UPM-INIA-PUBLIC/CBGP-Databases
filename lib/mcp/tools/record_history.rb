# frozen_string_literal: true

require_relative '../records'

module Mcp
  module Tools
    class RecordHistory < Mcp::Tool
      tool_name 'record_history'
      title "Record history"
      summary "Show how one record changed over time: each saved version and exactly which fields changed."
      description <<~TEXT
        Versions in date order. Version 1 is kind "created" with its starting values; later ones are kind "changed"
        with changes [{field, label, from, to}]. valid_from = when it took effect; valid_until = when the next version
        replaced it (null = current). A deleted record ends with kind "deleted" and the reason. One version only = no
        change since creation: say so. Current values are not repeated: use get_record. This reads the record's OWN
        versions; for connected records (projects, commitments, papers) use linked_records.

        Example: record_history {"form":"member","id":"34c37c2f-e6ec-49ca-97d7-aab18e432f9a"}
      TEXT
      param :form, type: 'string', required: true, description: 'Form name of the record'
      param :id, type: 'string', required: true, description: 'The record id (a UUID) returned by search_records or linked_records. Never a name or a DNI.'

      def self.run(args)
        ctx = Records::Context.new
        form = ctx.form!(args['form'])
        id = validate_iri_component!(args['id'].to_s.strip, field: 'id')
        versions = full_timeline(form_type: form.storage, primary_id: id)
        raise ToolError, "No history for #{form.name} id '#{id}'. Check the id with search_records." if versions.empty?

        states = versions.map { |v| fields_of(v[:triples]) }
        current = versions.last[:invalidated_at].nil? && versions.last[:graph_uri].include?('/context/')
        record = ctx.build_records(form, [ctx.graph_uri(form, id)]).first if current
        { record: record ? record.slice(:form, :id, :label) : { form: form.name, id: id, deleted: true },
          current: current, versions: build_versions(ctx, form, versions, states) }
      end

      # { questionclass => [values] } for one version's triples. Schema-agnostic
      # on purpose: it reads whatever was stored, so a field since removed from
      # the ontology still shows in old versions.
      def self.fields_of(triples)
        attr_types = triples.select { |t| t.predicate == RDF.type && t.object.to_s.start_with?(CBGP_NS) }
        by_node = attr_types.to_h { |t| [t.subject, t.object.to_s.delete_prefix(CBGP_NS)] }
        out = Hash.new { |h, k| h[k] = [] }
        triples.each do |t|
          next unless t.predicate.to_s == SIO_VALUE_PREDICATE && by_node.key?(t.subject)

          out[by_node[t.subject]] << t.object.to_s
        end
        out
      end

      def self.build_versions(ctx, form, versions, states)
        labels = ctx.fields(form.name).to_h { |f| [f[:questionclass], f] }
        versions.each_with_index.map do |v, i|
          nxt = versions[i + 1]
          entry = { version: i + 1, valid_from: v[:generated_at], valid_until: nxt ? nxt[:generated_at] : v[:invalidated_at] }
          if i.zero?
            entry[:kind] = 'created'
            entry[:values] = states[i].transform_values { |vals| vals.size == 1 ? vals.first : vals }
                                      .reject { |_, vals| vals.respond_to?(:empty?) && vals.empty? }
          else
            entry[:kind] = 'changed'
            entry[:changes] = diff(ctx, labels, states[i - 1], states[i])
          end
          entry[:reason] = v[:reason] if v[:reason]
          entry[:detail] = v[:detail] if v[:detail]
          entry
        end.tap { |list| mark_deleted(list, versions) }
      end

      # A last version that was invalidated with nothing after it is a deleted record.
      def self.mark_deleted(list, versions)
        last = versions.last
        return unless last[:invalidated_at]

        list << { version: list.size + 1, kind: 'deleted', valid_from: last[:invalidated_at],
                  reason: last[:reason], detail: last[:detail] }.compact
      end

      def self.diff(ctx, labels, before, after)
        (before.keys | after.keys).sort.filter_map do |name|
          old = before[name] || []
          new = after[name] || []
          next if old.sort == new.sort

          field = labels[name]
          { field: name, label: field ? field[:label] : name,
            from: shown(ctx, field, old), to: shown(ctx, field, new) }
        end
      end

      def self.shown(ctx, field, values)
        return nil if values.empty?

        list = values.map do |v|
          field && ctx.vocabulary_label(field, v) ? "#{ctx.vocabulary_label(field, v)} (#{v})" : v
        end
        list.size == 1 ? list.first : list
      end
    end
  end
end
