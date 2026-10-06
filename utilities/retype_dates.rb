#!/usr/bin/env ruby
# frozen_string_literal: true
#
# One-off migration (2026-10-06): turns date values that were stored as plain
# strings ("2026-01-31") into real xsd:date literals, in the current store
# AND the history store. Every NEW write already does this (sparql_literal,
# lib/queries.rb); this only catches up records written before that shipped.
# Without it a date-range search silently mismatches string-stored dates.
#
# Which attributes count as dates is read from the ontology (every field
# whose widget is a date picker - see CBGP::Dataset.fields_for), not listed
# here, so it follows the ontology. A value that is not a full YYYY-MM-DD
# date is left untouched and reported (nothing is ever guessed at).
#
# Idempotent: values already typed as xsd:date are not matched, so this is
# safe to re-run. Use --dry-run to count what would change.
#
# Usage:
#   ruby utilities/retype_dates.rb --dry-run
#   ruby utilities/retype_dates.rb

require 'dotenv'
Dotenv.load(File.expand_path('../.env', __dir__))
require 'require_all'
require_all '../app'

dry_run = ARGV.include?('--dry-run')

forms = get_databases(language: 'en').map(&:last) # [[label, form_id], ...]
date_classes = forms.flat_map { |f| CBGP::Dataset.fields_for(f) }
                    .select { |f| f[:class] == 'date' }
                    .map { |f| f[:questionclass] }.uniq.sort
abort 'No date fields found in the ontology - nothing to do.' if date_classes.empty?
warn "Date fields: #{date_classes.join(', ')}"

STRING_DATE = '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'

{ 'current store' => [DATABASE, DATABASE_UPDATE],
  'history store' => [HISTORY_DATABASE, HISTORY_DATABASE_UPDATE] }.each do |name, (reader, writer)|
  date_classes.each do |questionclass|
    validate_local_name!(questionclass, field: 'questionclass')
    where = <<~WHERE
      GRAPH ?g { ?a rdf:type cbgp:#{questionclass} ; sio:SIO_000300 ?v .
        FILTER(datatype(?v) = xsd:string && REGEX(STR(?v), "#{STRING_DATE}")) }
    WHERE
    count = reader.query("#{PREFIXES} SELECT (COUNT(*) AS ?n) WHERE { #{where} }").first[:n].to_i
    other = reader.query(<<~Q).first[:n].to_i
      #{PREFIXES} SELECT (COUNT(*) AS ?n) WHERE { GRAPH ?g { ?a rdf:type cbgp:#{questionclass} ; sio:SIO_000300 ?v .
        FILTER(datatype(?v) = xsd:string && !REGEX(STR(?v), "#{STRING_DATE}")) } }
    Q
    warn "  #{name}: #{questionclass}: #{count} to retype#{", #{other} NOT a full date (left as is)" if other.positive?}"
    next if dry_run || count.zero?

    writer.update(<<~U)
      #{PREFIXES}
      DELETE { GRAPH ?g { ?a sio:SIO_000300 ?v } }
      INSERT { GRAPH ?g { ?a sio:SIO_000300 ?d } }
      WHERE { #{where} BIND(STRDT(STR(?v), xsd:date) AS ?d) }
    U
  end
end
warn dry_run ? 'Dry run - nothing changed.' : 'Done.'
