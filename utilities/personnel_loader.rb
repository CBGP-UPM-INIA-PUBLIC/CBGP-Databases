require 'dotenv'
Dotenv.load(File.expand_path('../.env', __dir__)) # the project root's .env, not a separate utilities/.env copy - avoids config drift like the Virtuoso migration missing this file (2026-08-26)
require 'require_all'
require_all '../app'

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

member_fields = CBGP::Dataset.fields_for('member')

def method_for_header(field, member_fields)
  questionclass = HEADER_ALIASES.fetch(field, field)
  member_fields.find { |f| f[:questionclass] == questionclass }&.dig(:method)
end

CSV.foreach(ARGV[0], headers: true) do |row|
  ds = CBGP::Dataset.new(type: 'member')
  row.headers.each do |field| # field is the CSV column header (a questionclass fragment)
    next if field =~ /DISCARD/

    method_name = method_for_header(field, member_fields)
    abort "Dataset does not have a 'member' field matching CSV header '#{field}'" unless method_name

    ds.public_send("#{method_name}=", row[field]) # invoke the setter
  end
  puts "writing #{ds.primary_id}"
  ds.write_to_db
end
