#!/usr/bin/env ruby
# frozen_string_literal: true
#
# One-off migration (2026-07-28): stamps dcterms:type onto every existing
# "project"-dbname record's graph, using whatever local:has-defaults value
# it already has stored under the now-removed project_category field, then
# strips that now-dead field's triples from the record. See
# write_dataset_to_db_query in lib/queries.rb for the mechanism this
# backfills records up to (every NEW write already gets this
# automatically - this script only exists to catch up records written
# before that code shipped).
#
# Reads project_category's RAW triples directly via SPARQL rather than
# through CBGP::Dataset/fields_for, because the ontology no longer declares
# that questionclass at all - the normal field-loading machinery would
# never see it.
#
# Idempotent: a graph that already has dcterms:type is left untouched, so
# this is safe to re-run.
#
# A record with NEITHER project_category NOR dcterms:type already set (this
# should only ever be a stray, incompletely-written record - a real one
# always has one or the other) can't be backfilled at all, since there is
# nothing left anywhere to infer its form from. These are reported, never
# silently guessed at or silently deleted - pass --delete-unresolvable to
# actually remove them after reviewing the list.
#
# Usage:
#   ruby utilities/backfill_dcterms_type.rb                    # backfill + report only
#   ruby utilities/backfill_dcterms_type.rb --delete-unresolvable

require 'dotenv/load'
require 'require_all'
require_all '../app'

CATEGORY_TO_FORM = {
  'research-project' => 'project',
  'personnel-project' => 'personnel_project'
}.freeze

delete_unresolvable = ARGV.include?('--delete-unresolvable')

graphs = search_for_all_graphs(dataset_type: 'project')
warn "Found #{graphs.size} graph(s) under the 'project' dbname."

stamped = 0
already_done = 0
unresolvable = []

graphs.each do |graph_uri|
  already_typed = DATABASE.query(<<~ASK)
    #{PREFIXES}
    ASK { <#{graph_uri}> dcterms:type ?t }
  ASK

  if already_typed
    already_done += 1
    next
  end

  category_result = DATABASE.query(<<~CATEGORY_QUERY).first
    #{PREFIXES}
    SELECT ?value WHERE {
      GRAPH <#{graph_uri}> {
        ?ds sio:SIO_000008 ?attr .
        ?attr rdf:type cbgp:project_category ;
              sio:SIO_000300 ?value .
      }
    }
  CATEGORY_QUERY

  category_value = category_result&.bound?(:value) ? category_result[:value].to_s : nil
  form = CATEGORY_TO_FORM[category_value]

  unless form
    unresolvable << graph_uri
    next
  end

  DATABASE_UPDATE.update(<<~STAMP)
    #{PREFIXES}
    INSERT DATA { <#{graph_uri}> dcterms:type cbgp:#{form} . }
  STAMP

  # Clean up the now-dead project_category triples inside the named graph -
  # the attribute node, its rdf:type, its value, and the dataset node's link
  # to it.
  DATABASE_UPDATE.update(<<~CLEANUP)
    #{PREFIXES}
    DELETE WHERE {
      GRAPH <#{graph_uri}> {
        ?ds sio:SIO_000008 ?attr .
        ?attr rdf:type cbgp:project_category ;
              sio:SIO_000300 ?value .
      }
    }
  CLEANUP

  stamped += 1
  warn "Stamped #{graph_uri} -> dcterms:type cbgp:#{form} (was project_category=#{category_value})"
end

warn "\nDone. Stamped: #{stamped}, already had dcterms:type: #{already_done}, unresolvable: #{unresolvable.size}"

if unresolvable.any?
  warn "\nUnresolvable (no project_category AND no dcterms:type - form cannot be determined):"
  unresolvable.each { |g| warn "  #{g}" }

  if delete_unresolvable
    unresolvable.each do |graph_uri|
      delete_dataset_query(oldid: graph_uri, reason: 'deleted', detail: 'Unresolvable form during dcterms:type backfill')
      warn "Deleted #{graph_uri}"
    end
  else
    warn "\nRe-run with --delete-unresolvable to remove these, or leave them - they simply won't have dcterms:type."
  end
end
