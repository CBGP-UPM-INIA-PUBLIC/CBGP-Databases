require 'pony'
require 'open3'
require 'securerandom'

def get_databases
  warn 'getting databases'
  types = get_questionnaire_types_query # [{:questionnaire_type=>"https://w3id.org/CBGP-App#add-member", :questionnaire_label=>"Add/Edit Member"}, {:questionnaire_type=>"https://w3id.org/CBGP-App#add-project", :questionnaire_label=>"Add/Edit Project"}, {:questionnaire_type=>"https://w3id.org/CBGP-App#add-publication", :questionnaire_label=>"Add/Edit Publication"}]
  types = types.map { |hash| [hash[:questionnaire_label], hash[:questionnaire_type].match(/.*#(\S+)/)[1]] }
  warn types
  types
end

def generate_questionnaire(questionnaire_type:) # questionnaire_type comes in as code only
  Questionnaire.new(questionnaire_type: questionnaire_type) # questionnaire_type comes in as just the id)
  # warn questionnaire.inspect
end

def identifier_type(id: nil)
  type = false
  if id =~ /doi/
    type = 'doi'
  elsif id
    type = 'db_entry'
  end
  type
end
