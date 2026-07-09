# frozen_string_literal: true

require_relative 'queries'
require 'date'
require 'bigdecimal'

##############################################################################
# "Time machine" query layer over the SCD Type 2 history mechanism built in
# delete_dataset_query/write_dataset_to_db_query (queries.rb). A small set of
# generic, composable primitives — not one function per use case — designed
# so new questions ("who was active during X", "what changed on field Y")
# can be answered by combining these rather than writing bespoke SPARQL each
# time. Full design/rationale: .claude/plans/squishy-bouncing-unicorn.md
# (references .claude/plans/enumerated-zooming-sedgewick.md for Stage 1).
#
# Deliberately schema-agnostic throughout: every low-level read copies a
# graph's triples verbatim (CONSTRUCT), never filtered through
# CBGP::Dataset.fields_for's *current* field list. A history snapshot
# reflects whatever the ontology looked like when it was written, which can
# differ from today's — see the Stage 2 warning in the original plan file.
#
# Every public query function returns a plain RDF::Repository — real
# cbgp:/sio:/prov:/dcterms: triples (copied straight from the contributing
# snapshots, each kept in its own named graph — see the "Output wrapping"
# section below for why that matters) plus a small `local:` wrapper
# vocabulary describing the query result itself — so JSON-LD and TriG output
# are always just `repo.dump(:jsonld, prefixes: time_machine_prefixes)` /
# `repo.dump(:trig, prefixes: time_machine_prefixes)`: guaranteed consistent
# with each other since they come from the same repository, no separate
# hand-written serializer to keep in sync. Use the time_machine_prefixes
# helper, not the TIME_MACHINE_PREFIXES constant directly — RDF.rb's JSON-LD
# writer mutates whatever prefixes: hash it's handed (crashes outright if
# it's frozen; silently corrupts a shared one otherwise, which matters once
# this runs inside a long-lived Sinatra process serving many requests).
##############################################################################

TIME_MACHINE_PREFIXES = {
  cbgp: 'https://w3id.org/CBGP-App#',
  sio: 'http://semanticscience.org/resource/',
  dcterms: 'http://purl.org/dc/terms/',
  prov: 'http://www.w3.org/ns/prov#',
  local: 'urn:local:',
  xsd: 'http://www.w3.org/2001/XMLSchema#'
}.freeze

# A fresh, unfrozen copy of TIME_MACHINE_PREFIXES for each call to
# repo.dump(:jsonld/:trig, prefixes: ...) — see the comment above for why
# passing the frozen constant directly is unsafe.
def time_machine_prefixes
  TIME_MACHINE_PREFIXES.dup
end

CBGP_NS = TIME_MACHINE_PREFIXES[:cbgp]
LOCAL_NS = TIME_MACHINE_PREFIXES[:local]
PROV_NS = TIME_MACHINE_PREFIXES[:prov]
SIO_VALUE_PREDICATE = "#{TIME_MACHINE_PREFIXES[:sio]}SIO_000300"

PROV_PREFIX_DECL = 'PREFIX prov: <http://www.w3.org/ns/prov#>'

##############################################################################
# Low-level readers
##############################################################################

# Copies a graph's triples verbatim out of either repository. Schema-agnostic
# by construction: whatever predicates were actually written are what comes
# back, regardless of what the ontology looks like today.
#
# @param graph_uri [String]
# @param repository [SPARQL::Client] DATABASE or HISTORY_DATABASE
# @return [Array<RDF::Statement>]
def read_graph_triples(graph_uri:, repository:)
  repository.query(<<~SPARQL).statements
    #{PREFIXES}
    CONSTRUCT { ?s ?p ?o } WHERE { GRAPH <#{graph_uri}> { ?s ?p ?o } }
  SPARQL
end

# A still-current graph's own provenance (dcterms:created/modified, written
# by write_dataset_to_db_query into DATABASE's default graph).
#
# @param graph_uri [String]
# @return [Hash] { created:, modified: } — either key may be nil
def read_current_meta(graph_uri:)
  result = DATABASE.query(<<~SPARQL).first
    #{PREFIXES}
    SELECT ?created ?modified WHERE {
      OPTIONAL { <#{graph_uri}> dcterms:created  ?created }
      OPTIONAL { <#{graph_uri}> dcterms:modified ?modified }
    }
  SPARQL

  {
    created: result&.bound?(:created) ? result[:created].to_s : nil,
    modified: result&.bound?(:modified) ? result[:modified].to_s : nil
  }
end

##############################################################################
# Graph enumeration
##############################################################################

# Every currently-live graph URI of a given form type.
#
# @param form_type [String] e.g. "member"
# @return [Array<String>]
def current_graph_uris(form_type:)
  DATABASE.query(<<~SPARQL).map { |r| r[:g].to_s }
    #{PREFIXES}
    SELECT DISTINCT ?g WHERE { GRAPH ?g { ?s a cbgp:#{form_type} } }
  SPARQL
end

# Every history snapshot of a form type, each with its own graph-level
# metadata, in a single query — optionally scoped to one record's
# primary_id. The verbatim-copy design means the original
# `rdf:type cbgp:<form_type>` triple survives into every snapshot, so
# enumerating history graphs is the same query shape as current_graph_uris,
# just pointed at HISTORY_DATABASE; all versions of one record share the
# .../form_type/history/<primary_id>/ URI prefix by construction (see
# delete_dataset_query), which is what makes the primary_id scoping cheap.
#
# @param form_type [String]
# @param primary_id [String, nil] scope to one record's history if given
# @return [Array<Hash>] { graph_uri:, generated_at:, invalidated_at:,
#   reason:, detail: } — generated_at is always present (delete_dataset_query
#   always sets prov:generatedAtTime); the rest may be nil
def history_snapshots(form_type:, primary_id: nil)
  prefix = "#{BASE_URI}#{form_type}/history/#{primary_id}"
  prefix += '/' if primary_id

  HISTORY_DATABASE.query(<<~SPARQL).map do |r|
    #{PREFIXES}
    #{PROV_PREFIX_DECL}
    SELECT ?g ?generated ?invalidated ?reason ?detail WHERE {
      ?g prov:generatedAtTime ?generated .
      OPTIONAL { ?g prov:invalidatedAtTime ?invalidated }
      OPTIONAL { ?g local:history-reason ?reason }
      OPTIONAL { ?g local:history-detail ?detail }
      FILTER(STRSTARTS(STR(?g), "#{prefix}"))
    }
  SPARQL
    {
      graph_uri: r[:g].to_s,
      generated_at: r[:generated]&.to_s,
      invalidated_at: r.bound?(:invalidated) ? r[:invalidated].to_s : nil,
      reason: r.bound?(:reason) ? r[:reason].to_s : nil,
      detail: r.bound?(:detail) ? r[:detail].to_s : nil
    }
  end
end

# Extracts the primary_id out of a history graph URI
# (".../form_type/history/<primary_id>/<uuid>") — the inverse of the URI
# pattern delete_dataset_query mints.
def primary_id_from_history_graph(graph_uri:, form_type:)
  prefix = "#{BASE_URI}#{form_type}/history/"
  graph_uri.delete_prefix(prefix).split('/').first
end

##############################################################################
# Identifier resolution
##############################################################################

# Resolves a stable identifier (e.g. an ORCiD) to a record's primary_id.
# Exact match, not the fuzzy/accent-insensitive search machinery — real
# identifiers don't need that. Checks current state first (the common case),
# then falls back to scanning history so a former employee/deleted record
# with no current graph is still resolvable.
#
# @param form_type [String] e.g. "member"
# @param questionclass [String] e.g. "member_orcid"
# @param value [String] the identifier value to match, exactly
# @return [String, nil] the record's primary_id, or nil if not found anywhere
def find_primary_id(form_type:, questionclass:, value:)
  escaped = escape_for_literal(value)
  attr_match = <<~PATTERN
    ?dataset sio:SIO_000008 ?attr ;
             sio:SIO_000671 ?idnode .
    ?attr rdf:type cbgp:#{questionclass} ;
          sio:SIO_000300 "#{escaped}" .
    ?idnode rdf:type sio:SIO_000115 ;
            sio:SIO_000300 ?id .
  PATTERN

  current = DATABASE.query(<<~SPARQL).first
    #{PREFIXES}
    SELECT ?id WHERE { GRAPH ?g { #{attr_match} } }
  SPARQL
  return current[:id].to_s if current

  history_prefix = "#{BASE_URI}#{form_type}/history/"
  match = HISTORY_DATABASE.query(<<~SPARQL).first
    #{PREFIXES}
    SELECT ?id WHERE {
      GRAPH ?g { #{attr_match} }
      FILTER(STRSTARTS(STR(?g), "#{history_prefix}"))
    }
  SPARQL
  match ? match[:id].to_s : nil
end

##############################################################################
# One record's full version history
##############################################################################

# Every version of one record, in chronological order: every history
# snapshot plus the still-current version, if any. Direct answer to "give
# me the complete history of record X from creation until today."
#
# @param form_type [String]
# @param primary_id [String]
# @return [Array<Hash>] each entry: { graph_uri:, triples:, generated_at:,
#   invalidated_at: (nil if still current), reason: (nil if still current),
#   detail: (nil if still current) }, sorted by generated_at ascending
def full_timeline(form_type:, primary_id:)
  versions = history_snapshots(form_type: form_type, primary_id: primary_id).map do |snap|
    snap.merge(triples: read_graph_triples(graph_uri: snap[:graph_uri], repository: HISTORY_DATABASE))
  end

  current_graph = "#{BASE_URI}#{form_type}/context/#{primary_id}"
  current_triples = read_graph_triples(graph_uri: current_graph, repository: DATABASE)
  if current_triples.any?
    meta = read_current_meta(graph_uri: current_graph)
    versions << {
      graph_uri: current_graph,
      triples: current_triples,
      generated_at: meta[:modified] || meta[:created],
      invalidated_at: nil,
      reason: nil,
      detail: nil
    }
  end

  versions.sort_by { |v| v[:generated_at].to_s }
end

##############################################################################
# "Latest known state" across every record of a type
##############################################################################

# For every record of a type, the most-recently-known state: the current
# graph if it still exists, otherwise the temporally-last history snapshot
# (by invalidated_at) if the record was since deleted. Makes queries over
# "all records of a type" durable/reproducible — a record deleted after
# being queried doesn't silently vanish from a later re-run of the same
# query, it just answers from its last known state.
#
# @param form_type [String]
# @return [Array<Hash>] { primary_id:, graph_uri:, is_current:, triples: }
def latest_known_snapshots(form_type:)
  current_by_id = current_graph_uris(form_type: form_type).each_with_object({}) do |g, hash|
    hash[g.split('/').last] = g
  end

  by_id = history_snapshots(form_type: form_type).group_by do |snap|
    primary_id_from_history_graph(graph_uri: snap[:graph_uri], form_type: form_type)
  end

  deleted_entries = by_id.filter_map do |id, snaps|
    next if id.nil? || current_by_id.key?(id)

    latest = snaps.max_by { |s| s[:invalidated_at].to_s }
    { primary_id: id, graph_uri: latest[:graph_uri], is_current: false }
  end

  current_entries = current_by_id.map { |id, g| { primary_id: id, graph_uri: g, is_current: true } }

  (current_entries + deleted_entries).map do |entry|
    repository = entry[:is_current] ? DATABASE : HISTORY_DATABASE
    entry.merge(triples: read_graph_triples(graph_uri: entry[:graph_uri], repository: repository))
  end
end

##############################################################################
# Generic filter/aggregate over "latest known state"
##############################################################################

# Reads one questionclass's value(s) out of a snapshot's raw triples —
# schema-agnostic (works against whatever was actually written, not today's
# fields_for), so this is safe to use on old/since-removed fields too.
#
# @param triples [Array<RDF::Statement>]
# @param questionclass [String]
# @return [Array<String>] every matching literal value (empty if none;
#   Multiple-cardinality fields naturally return more than one)
def snapshot_field_values(triples:, questionclass:)
  attr_type = RDF::URI("#{CBGP_NS}#{questionclass}")
  attribute_nodes = triples.select { |t| t.predicate == RDF.type && t.object == attr_type }.map(&:subject)

  triples.select { |t| attribute_nodes.include?(t.subject) && t.predicate.to_s == SIO_VALUE_PREDICATE }
         .map { |t| t.object.to_s }
end

# Keeps only the snapshots (from latest_known_snapshots) matching every
# facets[questionclass] => value pair (exact match; any number of facets,
# including zero) AND every date_ranges[questionclass] => {start:, end:}
# range (a snapshot must satisfy *all* of them; any number of date ranges,
# including zero — mirrors the existing search form's ability to filter on
# more than one date-range field at once). Either bound in a range may be
# omitted/blank for an open-ended range. Neither the facet field(s) nor the
# date field(s) are hardcoded — same shape whether filtering on
# project_type, member_status, or several of each at once.
#
# @param form_type [String]
# @param facets [Hash{String=>String}] questionclass => required exact value
# @param date_ranges [Hash{String=>Hash}] questionclass => { start:, end: }
#   ("YYYY-MM-DD" strings; either may be nil/blank for an open bound)
# @return [Array<Hash>] matching entries from latest_known_snapshots
def filter_snapshots_during(form_type:, facets: {}, date_ranges: {})
  latest_known_snapshots(form_type: form_type).select do |snap|
    facets.all? { |qc, value| snapshot_field_values(triples: snap[:triples], questionclass: qc).include?(value) } &&
      date_ranges.all? do |qc, range|
        date_in_range?(snap, date_field: qc, start_date: range[:start], end_date: range[:end])
      end
  end
end

def date_in_range?(snapshot, date_field:, start_date:, end_date:)
  return true if start_date.to_s.strip.empty? && end_date.to_s.strip.empty?

  values = snapshot_field_values(triples: snapshot[:triples], questionclass: date_field)
  return false if values.empty?

  values.any? do |v|
    d = Date.parse(v)
    (start_date.to_s.strip.empty? || d >= Date.parse(start_date)) &&
      (end_date.to_s.strip.empty? || d <= Date.parse(end_date))
  rescue ArgumentError
    false
  end
end

# Sums one numeric-looking field across an already-filtered snapshot set.
# A future count_by_facet/average_numeric_field/etc. would be a same-shape
# sibling of this, not a rewrite of filter_snapshots_during.
#
# @param snapshots [Array<Hash>] from filter_snapshots_during (or
#   latest_known_snapshots directly)
# @param questionclass [String]
# @return [BigDecimal]
def sum_numeric_field(snapshots:, questionclass:)
  snapshots.sum(BigDecimal(0)) do |snap|
    snapshot_field_values(triples: snap[:triples], questionclass: questionclass)
      .sum(BigDecimal(0)) { |v| BigDecimal(v.to_s) }
  rescue ArgumentError
    BigDecimal(0)
  end
end

##############################################################################
# Output wrapping: RDF::Repository results (named graphs, not RDF::Graph)
#
# A record's internal attribute-node URIs (e.g. .../member_status) are
# STABLE across versions by construction (same primary_id + questionclass =>
# same node URI every time it's written — see write_dataset_to_db_query).
# That's exactly right for the real store, where each version lives in its
# own named graph. But it means naively merging several versions' triples
# into one flat RDF::Graph silently collides them: verified live —
# member_status came back as `sio:SIO_000300 "Active", "Inactive"` on the
# SAME node, with no way to tell which version either value belonged to.
#
# Fix: keep each contributing snapshot's triples in their own named graph
# within an RDF::Repository, graph_name = the *real* graph URI it came from
# (mirroring the actual store's own structure exactly). The query-result
# wrapper/meta triples go in the default graph. JSON-LD represents this
# faithfully via nested @graph; plain Turtle has no named-graph syntax, so
# the non-JSON-LD output format here is TriG (Turtle + GRAPH blocks — same
# triple syntax, still trivially human-readable/diffable).
##############################################################################

def new_query_result_uri
  RDF::URI("#{BASE_URI}query-result/#{SecureRandom.uuid}")
end

# Inserts triples into a repository's named graph, reusing each statement's
# subject/predicate/object but stamping graph_name — read_graph_triples'
# CONSTRUCT results carry no graph_name of their own (CONSTRUCT output is
# graph-agnostic by SPARQL semantics), so callers of this need not worry
# about creating fresh RDF::Statement objects themselves.
def insert_into_named_graph(repository:, triples:, graph_name:)
  repository.insert(*triples.map { |t| RDF::Statement.new(t.subject, t.predicate, t.object, graph_name: graph_name) })
end

# Wraps full_timeline's result for one record (resolved by an identifying
# field, e.g. ORCiD) as an RDF::Repository: the query-result node links to
# every version via local:version, and each version's own real triples
# (copied verbatim from its snapshot, kept in their own named graph so
# same-named fields across versions never collide) plus its
# prov:/local:history-* provenance are included as-is. Not member-specific —
# works for any form_type.
#
# @param form_type [String]
# @param questionclass [String] identifying field, e.g. "member_orcid"
# @param value [String]
# @return [RDF::Repository, nil] nil if no record with that identifier is
#   found anywhere (current or history)
def record_history_result(form_type:, questionclass:, value:)
  primary_id = find_primary_id(form_type: form_type, questionclass: questionclass, value: value)
  return nil unless primary_id

  timeline = full_timeline(form_type: form_type, primary_id: primary_id)

  repo = RDF::Repository.new
  result = new_query_result_uri
  repo << [result, RDF.type, RDF::URI("#{LOCAL_NS}TimeMachineResult")]
  repo << [result, RDF::URI("#{LOCAL_NS}queryType"), RDF::Literal('record-history')]
  repo << [result, RDF::URI("#{LOCAL_NS}executedAt"),
           RDF::Literal.new(Time.now.utc.iso8601, datatype: RDF::XSD.dateTime)]
  repo << [result, RDF::URI("#{CBGP_NS}#{questionclass}"), RDF::Literal(value)]

  timeline.each do |version|
    version_uri = RDF::URI(version[:graph_uri])
    repo << [result, RDF::URI("#{LOCAL_NS}version"), version_uri]
    insert_into_named_graph(repository: repo, triples: version[:triples], graph_name: version_uri)
    if version[:generated_at]
      repo << [version_uri, RDF::URI("#{PROV_NS}generatedAtTime"),
               RDF::Literal.new(version[:generated_at], datatype: RDF::XSD.dateTime)]
    end
    if version[:invalidated_at]
      repo << [version_uri, RDF::URI("#{PROV_NS}invalidatedAtTime"),
               RDF::Literal.new(version[:invalidated_at], datatype: RDF::XSD.dateTime)]
    end
    repo << [version_uri, RDF::URI("#{LOCAL_NS}history-reason"), RDF::Literal(version[:reason])] if version[:reason]
    repo << [version_uri, RDF::URI("#{LOCAL_NS}history-detail"), RDF::Literal(version[:detail])] if version[:detail]
  end

  repo
end

# Wraps a filter_snapshots_during result (optionally summed via
# sum_numeric_field) as an RDF::Repository: the query-result node records
# exactly what was asked (facets, date ranges, which field was summed, if
# any) plus every contributing record's own real triples (each in its own
# named graph, same collision-avoidance reasoning as record_history_result),
# linked via local:contributingRecord. Generic over which facets/fields were
# used — nothing here is specific to funding or projects. sum_field is
# optional: omit it for a plain "what matched" search result (queryType
# temporal-search); supply it to also get a total (queryType
# temporal-aggregate) — same underlying query either way, just whether a sum
# was requested on top of it.
#
# @param form_type [String]
# @param facets [Hash{String=>String}]
# @param date_ranges [Hash{String=>Hash}] questionclass => { start:, end: }
# @param sum_field [String, nil] questionclass to sum, if any
# @return [RDF::Repository]
def temporal_search_result(form_type:, facets: {}, date_ranges: {}, sum_field: nil)
  snapshots = filter_snapshots_during(form_type: form_type, facets: facets, date_ranges: date_ranges)

  repo = RDF::Repository.new
  result = new_query_result_uri
  repo << [result, RDF.type, RDF::URI("#{LOCAL_NS}TimeMachineResult")]
  repo << [result, RDF::URI("#{LOCAL_NS}queryType"), RDF::Literal(sum_field ? 'temporal-aggregate' : 'temporal-search')]
  repo << [result, RDF::URI("#{LOCAL_NS}executedAt"),
           RDF::Literal.new(Time.now.utc.iso8601, datatype: RDF::XSD.dateTime)]
  repo << [result, RDF::URI("#{LOCAL_NS}queriedFormType"), RDF::Literal(form_type)]
  facets.each { |qc, value| repo << [result, RDF::URI("#{CBGP_NS}#{qc}"), RDF::Literal(value)] }
  date_ranges.each do |qc, range|
    repo << [result, RDF::URI("#{LOCAL_NS}queriedDateField"), RDF::Literal(qc)]
    if range[:start].to_s.strip != ''
      repo << [result, RDF::URI("#{LOCAL_NS}queriedIntervalStart"),
               RDF::Literal.new(range[:start], datatype: RDF::XSD.date)]
    end
    if range[:end].to_s.strip != ''
      repo << [result, RDF::URI("#{LOCAL_NS}queriedIntervalEnd"),
               RDF::Literal.new(range[:end], datatype: RDF::XSD.date)]
    end
  end
  repo << [result, RDF::URI("#{LOCAL_NS}recordCount"), RDF::Literal.new(snapshots.size, datatype: RDF::XSD.integer)]

  if sum_field
    total = sum_numeric_field(snapshots: snapshots, questionclass: sum_field)
    repo << [result, RDF::URI("#{LOCAL_NS}summedField"), RDF::Literal(sum_field)]
    repo << [result, RDF::URI("#{LOCAL_NS}totalAmount"), RDF::Literal.new(total.to_s('F'), datatype: RDF::XSD.decimal)]
  end

  snapshots.each do |snap|
    record_uri = RDF::URI(snap[:graph_uri])
    repo << [result, RDF::URI("#{LOCAL_NS}contributingRecord"), record_uri]
    insert_into_named_graph(repository: repo, triples: snap[:triples], graph_name: record_uri)
  end

  repo
end
