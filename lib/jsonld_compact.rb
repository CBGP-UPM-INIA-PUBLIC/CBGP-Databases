# frozen_string_literal: true

require_relative 'history_queries' # pulls in queries.rb too; reuses time_machine_prefixes/BASE_URI

# Compact JSON-LD serialization for core-DB records, matching the shape
# History's existing repo.dump(:jsonld, prefixes: time_machine_prefixes)
# already produces (see lib/history_queries.rb) - flat, plain-JSON-shaped,
# but keeping @id (the record's own graph URI) and real questionclass keys
# via a shared @context. That's what lets a value returned by one MCP
# server's tool be passed directly into the other server's tool arguments
# (e.g. a search_records result's @id straight into record_history's
# primary_id) without a lossy label -> identifier remapping step.
#
# lib/queries.rb/lib/dataset_classes.rb have no JSON serialization of their
# own today (CBGP::Dataset has no to_h/to_json) - this is genuinely new
# code, built directly on fetch_datasets_raw_data's existing output shape
# (Hash{dataset: graph_uri, questionclass_sym => value_or_array_of_strings})
# rather than going through CBGP::Dataset, which carries UI-oriented
# machinery (formulas, widget defaults) these read-only MCP tools don't need.
module JsonldCompact
  # Reuses the exact same prefix set History's dumps already use, so both
  # MCP servers' output shares one @context rather than two that happen to
  # look similar.
  def self.context
    time_machine_prefixes.transform_keys(&:to_s).merge('@base' => BASE_URI)
  end

  # @param form_type [String] the ontology form class, e.g. "member"
  # @param raw_record [Hash] one entry from fetch_datasets_raw_data's output
  #   - {dataset: graph_uri, questionclass_sym => value_or_array, ...}
  # @return [Hash] a compact-JSON-LD-shaped Hash (caller calls .to_json)
  def self.serialize_record(form_type:, raw_record:)
    record = raw_record.dup
    graph_uri = record.delete(:dataset)

    fields = record.each_with_object({}) { |(questionclass, value), hash| hash[questionclass.to_s] = value }

    {
      '@context' => context,
      '@id' => graph_uri,
      '@type' => "cbgp:#{form_type}"
    }.merge(fields)
  end

  # @param form_type [String]
  # @param raw_records [Array<Hash>]
  # @return [Array<Hash>]
  def self.serialize_records(form_type:, raw_records:)
    raw_records.map { |r| serialize_record(form_type: form_type, raw_record: r) }
  end
end
