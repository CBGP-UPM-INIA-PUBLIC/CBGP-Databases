require 'dotenv/load'
require 'require_all'
require_all 'app'

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

CSV.foreach(ARGV[0], headers: true) do |row|
  ds = CBGP::Dataset.new(type: 'member')
  # warn row.headers
  row.headers.each do |field| # field is the method name
    next if field =~ /DISCARD/

    warn "#{field}=#{row[field]}\n"
    ds.public_send("#{field}=", row[field]) # invoke the setter
  end
  ds.write_to_db
end
