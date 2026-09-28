require 'dotenv'
Dotenv.load(File.expand_path('../.env', __dir__)) # the project root's .env, not a separate utilities/.env copy - avoids config drift like the Virtuoso migration missing this file (2026-08-26)
require 'require_all'
require_all '../app'
require 'date'

abort 'must provide input csv file' unless ARGV[0]

# a dataset has #fields which is a sequence-ordered list of
# @fields << { q: q, questionclass: questionclass, label: result[:label].to_s,
#  widget: result[:widget].to_s.downcase, method: method_name,
#  class: klass, cardinality: cardinality, answers: answers_uri,
#  is_external_primary: is_external_primary, sequence: sequence,
#  sectionid: sectionid, sectionlabel: sectionlabel }
#
# ds also has getter and setter methods for each method_name
# Sara has set the value of each spreadsheet cell to match the classname!  Thank you!!
#
# CSV headers are the ontology's questionclass fragments (e.g. "member_name",
# not the Dataset setter method "name") - resolved below via fields_for
# rather than assumed to already be method names, since Sara's exports use
# the questionclass form. A couple of headers don't match a questionclass
# exactly (a stray singular/plural, most likely just how the export was
# typed) - HEADER_ALIASES covers those known cases explicitly rather than
# guessing with a fuzzy match.
HEADER_ALIASES = {
  'member_surname' => 'member_surnames',
  'member_orcids' => 'member_orcid'
}.freeze

# One-off bulk history load (2026-09-28): unlike a normal form submission,
# each real person in this export has MULTIPLE rows - one per historical
# "stint" (a contract period, a status change, etc.) - meant to become a
# genuine SCD Type 2 version history for that one person, not N disconnected
# records. Grouped by member_cbgp_id (added to this export by a separate
# CBGP-ID merge pass, see the CBGP Databases desktop folder) - NOT the
# ontology's own primary_id, which is a fresh UUID this script mints once per
# real person and reuses across all of their row-versions.
#
# We can't know the TRUE date each row was originally entered into the old
# system, so every version written here gets today's transaction timestamp
# (dcterms:created/modified) - that's fine, and doesn't need any code
# changes, since write_dataset_to_db_query already always stamps "now".
# What DOES matter, since every transaction timestamp will be ~today, is the
# ORDER we submit the writes in for a given person: that's what the History
# DB will treat as "what happened when", not any date field. So:
#   1. Fix known data-entry errors: some rows have member_start_date and
#      member_end_date entered backwards (confirmed real, ~14% of rows) -
#      swap them whenever end < start, BEFORE sorting, so the correction
#      also fixes the ordering.
#   2. Sort each person's rows by (corrected start, corrected end) ascending
#      - the file's own row order is not trusted to already be chronological
#      (confirmed: sorting by start date alone reorders many people's rows
#      relative to file order). A blank end (still-ongoing) sorts last
#      among any tied start dates.
#   3. Write the ordered rows for each person under ONE reused primary_id -
#      the first write is a plain create (oldid: nil), every subsequent
#      write passes oldid: that same primary_id, so it supersedes the
#      previous version via the normal SCD history mechanism
#      (write_dataset_to_db_query) instead of creating an unrelated record.
member_fields = CBGP::Dataset.fields_for('member')

def method_for_header(field, member_fields)
  questionclass = HEADER_ALIASES.fetch(field, field)
  member_fields.find { |f| f[:questionclass] == questionclass }&.dig(:method)
end

# widget-type is a full URI (e.g. "https://w3id.org/CBGP-App#date") - only
# the fragment matters here.
def date_field?(header, member_fields)
  questionclass = HEADER_ALIASES.fetch(header, header)
  field = member_fields.find { |f| f[:questionclass] == questionclass }
  field && field[:widget].to_s.split('#').last == 'date'
end

# This export's dates are DD/MM/YYYY (confirmed: values like "31/12/2012"
# appear, which is only valid as day/month). Stored fields are class
# "string" (not xsd:date), but validate_date!/build_search_query's date-range
# search both expect YYYY-MM-DD - convert here so this data behaves like any
# real form submission (an HTML date-picker always submits YYYY-MM-DD).
def parse_export_date(value)
  value = value.to_s.strip
  return nil if value.empty?

  Date.strptime(value, '%d/%m/%Y')
rescue ArgumentError
  warn "  WARNING: could not parse date '#{value}' as DD/MM/YYYY - leaving that field blank"
  nil
end

# Real, formal ontology answer ids for a controlled-vocabulary field's
# answer block (radio/hiddenfield/treeselector - see
# controlled_vocabulary_field?, lib/core.rb), fetched once per distinct
# block and cached. Some of this export's values are informal group/lab
# descriptions rather than a real answer id (e.g. "Pablo Rodriguez/Emilia:
# Phytopathogenic bacteria" for member_research_area_group) - genuinely not
# yet in the ontology's tree, not a parsing bug - see MISSED_VALUES below.
# rubocop:disable Style/MutableConstant -- both intentionally mutated caches/accumulators
VALID_ANSWER_IDS_CACHE = {}

def valid_answer_ids_for(field)
  ablockid = field[:answers].to_s.split('#').last
  VALID_ANSWER_IDS_CACHE[ablockid] ||= begin
    # rdfs:subClassOf+ (transitive property path), not get_answer_block_query
    # (only direct/one-level subclasses) - member_category and
    # member_research_area_group are TREESELECTOR fields with a real
    # multi-level hierarchy, so a real leaf answer (e.g.
    # "project_funded_ptgas") is several rdfs:subClassOf hops below the
    # block root, not a direct child of it. Using the shallow query here
    # would have flagged nearly every genuinely valid value across both
    # fields as "missing from the ontology" - not a real gap, a validation
    # bug. + works uniformly for a flat (single-level) block too.
    q = <<~SPARQL
      #{PREFIXES}
      SELECT DISTINCT ?aid WHERE { ?aid rdfs:subClassOf+ cbgp:#{ablockid} . }
    SPARQL
    SPARQL.parse(q).execute($ontology).map { |row| row[:aid].to_s.split('#').last }.to_set
  end
end

# Rows accumulated here get written to a "*_missed.csv" report at the end -
# every non-blank controlled-vocabulary value that doesn't match a real
# ontology answer id, for Sara to review and decide whether to add as a new
# formal answer later (not something this one-off script should guess at
# inventing itself). Distinct from a blank/"-" cell (silently skipped, see
# below), which just means "no value given", not "value not yet in the
# ontology".
MISSED_VALUES = []
# rubocop:enable Style/MutableConstant

# True (and logs to MISSED_VALUES) if this is a controlled-vocabulary field
# whose value isn't one of that field's real ontology answer ids - the
# caller should skip setting it. Always false for free-text/date/etc.
# fields, which have no fixed answer set to check against.
def missed_ontology_value?(cbgp_id:, primary_id:, field:, value:, member_fields:)
  questionclass = HEADER_ALIASES.fetch(field, field)
  field_def = member_fields.find { |f| f[:questionclass] == questionclass }
  return false unless controlled_vocabulary_field?(field_def)
  return false if valid_answer_ids_for(field_def).include?(value.strip)

  MISSED_VALUES << { cbgp_id: cbgp_id, primary_id: primary_id, questionclass: questionclass, value: value.strip }
  warn "  MISSED: cbgp_id=#{cbgp_id} #{questionclass}=#{value.strip.inspect} is not a real " \
       "#{field_def[:answers].to_s.split('#').last} answer id - logged, not written"
  true
end

rows = CSV.read(ARGV[0], headers: true).map(&:to_h)
by_person = rows.group_by { |r| r['member_cbgp_id'] }

swap_count = 0
person_count = 0
version_count = 0

by_person.each do |cbgp_id, person_rows|
  # Step 1: fix inverted start/end, on the raw row hash, before sorting.
  corrected_rows = person_rows.map do |row|
    row = row.dup
    start_date = parse_export_date(row['member_start_date'])
    end_date = parse_export_date(row['member_end_date'])
    if start_date && end_date && end_date < start_date
      row['member_start_date'], row['member_end_date'] = row['member_end_date'], row['member_start_date']
      swap_count += 1
      warn "  fixed inverted start/end for cbgp_id=#{cbgp_id} (was #{end_date} - #{start_date})"
    end
    row
  end

  # Step 2: most-likely-real chronological order. A blank/unparseable end
  # date (still-ongoing) sorts after any real date at the same start.
  far_future = Date.new(9999, 12, 31)
  ordered_rows = corrected_rows.sort_by do |row|
    [parse_export_date(row['member_start_date']) || far_future,
     parse_export_date(row['member_end_date']) || far_future]
  end

  primary_id = SecureRandom.uuid
  person_count += 1
  puts "cbgp_id=#{cbgp_id}: #{ordered_rows.size} version(s) -> primary_id=#{primary_id}"

  ordered_rows.each_with_index do |row, index|
    ds = CBGP::Dataset.new(type: 'member')
    ds.primary_id = primary_id

    row.each do |field, value|
      next if field.to_s =~ /DISCARD/
      # "-" is this export's own placeholder for "no value" (seen elsewhere
      # in the same export, e.g. a blank phone number) - harmless if left as
      # literal text in a free-text field, but crashes write_dataset_to_db_query's
      # history-diff summary for a controlled-vocabulary field, which tries
      # to resolve it as an answer-class id. Treat it as blank everywhere,
      # same as a genuinely empty cell.
      next if value.to_s.strip.empty? || value.to_s.strip == '-'

      method_name = method_for_header(field, member_fields)
      abort "Dataset does not have a 'member' field matching CSV header '#{field}'" unless method_name

      next if missed_ontology_value?(cbgp_id: cbgp_id, primary_id: primary_id, field: field, value: value,
                                     member_fields: member_fields)

      if date_field?(field, member_fields)
        parsed = parse_export_date(value)
        next unless parsed

        value = parsed.iso8601
      end

      ds.public_send("#{method_name}=", value)
    end

    oldid = index.zero? ? nil : primary_id
    CBGP::Dataset.write_to_db(dataset: ds, oldid: oldid)
    version_count += 1
  end
end

missed_path = "#{ARGV[0].sub(/\.csv\z/i, '')}_missed.csv"
CSV.open(missed_path, 'w') do |csv|
  csv << %w[cbgp_id primary_id questionclass value]
  MISSED_VALUES.each { |m| csv << [m[:cbgp_id], m[:primary_id], m[:questionclass], m[:value]] }
end

puts
puts "Done. #{person_count} people, #{version_count} record-versions written, " \
     "#{swap_count} inverted start/end pairs corrected."
puts "#{MISSED_VALUES.size} controlled-vocabulary value(s) didn't match a real ontology answer id - see #{missed_path}"
