#!/usr/bin/env ruby
# frozen_string_literal: true

# CLI demo of the "time machine" query layer (lib/history_queries.rb) built
# over SCD Type 2 history. Two worked examples, both thin compositions of
# the same generic primitives — see lib/history_queries.rb's own docs and
# .claude/plans/squishy-bouncing-unicorn.md for the full design.
#
# Usage:
#   ruby utilities/time_machine.rb history <form_type> <questionclass> <value> [jsonld|trig]
#     e.g. ruby utilities/time_machine.rb history member member_orcid 0000-0002-1234-5678
#
#   ruby utilities/time_machine.rb funding <form_type> <facet_questionclass> <facet_value> \
#     <date_field> <start_date> <end_date> <sum_field> [jsonld|trig]
#     e.g. ruby utilities/time_machine.rb funding project project_type Articulo-60 \
#       project_start_date 2025-01-01 2025-06-30 project_total_funding
#
# Output format defaults to jsonld. Plain Turtle isn't offered: a result can
# span several contributing records/versions whose same-named internal
# fields would otherwise collide if flattened into one graph (see
# lib/history_queries.rb's "Output wrapping" section) — TriG (Turtle +
# named-graph blocks, same triple syntax) is the closest equivalent.

require 'dotenv/load'
require 'require_all'
require_all '../app'

Thread.current[:language] = 'en'

def usage_and_exit
  warn <<~USAGE
    Usage:
      ruby utilities/time_machine.rb history <form_type> <questionclass> <value> [jsonld|trig]
      ruby utilities/time_machine.rb funding <form_type> <facet_questionclass> <facet_value> <date_field> <start_date> <end_date> <sum_field> [jsonld|trig]
  USAGE
  exit 1
end

command = ARGV[0]
usage_and_exit unless %w[history funding].include?(command)

case command
when 'history'
  form_type, questionclass, value, format = ARGV[1..4]
  usage_and_exit unless form_type && questionclass && value

  format ||= 'jsonld'
  usage_and_exit unless %w[jsonld trig].include?(format)

  repo = record_history_result(form_type: form_type, questionclass: questionclass, value: value)
  if repo.nil?
    warn "No #{form_type} record found with #{questionclass} = #{value} (checked current and history)"
    exit 1
  end

  puts repo.dump(format.to_sym, prefixes: time_machine_prefixes)

when 'funding'
  form_type, facet_qc, facet_value, date_field, start_date, end_date, sum_field, format = ARGV[1..8]
  usage_and_exit unless form_type && facet_qc && facet_value && date_field && start_date && end_date && sum_field

  format ||= 'jsonld'
  usage_and_exit unless %w[jsonld trig].include?(format)

  repo = temporal_search_result(
    form_type: form_type,
    facets: { facet_qc => facet_value },
    date_ranges: { date_field => { start: start_date, end: end_date } },
    sum_field: sum_field
  )
  puts repo.dump(format.to_sym, prefixes: time_machine_prefixes)
end
