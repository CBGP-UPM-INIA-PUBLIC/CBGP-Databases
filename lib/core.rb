require_relative "questionnaire"
require_relative "publications_classes"
require_relative "members_classes"
require_relative "projects_classes"
require "pony"
require "open3"
require "securerandom"

def get_databases
  [%w[Publications publications], %w[Personnel personnel], %w[Projects projects]]
end

def generate_questionnaire(questionnaire_type:) # questionnaire_type comes in as code only
  Questionnaire.new(questionnaire_type: questionnaire_type) # questionnaire_type comes in as just the id)
  # warn questionnaire.inspect
end

