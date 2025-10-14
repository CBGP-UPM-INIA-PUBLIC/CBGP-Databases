require_relative 'queries'
require_relative 'core'
require 'uuidtools'

module CBGP
  class Dataset
    attr_reader :fields, :form_type, :primary_id # Expose sorted fields for UI ordering

    def initialize(type:, primary_id: SecureRandom.uuid)  # passed database type e.g. add_members
      @form_type = type
      @primary_id = primary_id
      sections = get_questionnaire_sections_query(questionnaire_type: type) # "add-publications", "add-project" "add-member"
      # abort sections.inspect
      # SELECT ?sec (str(?seclab) as ?label)
      sections.each do |thissection|
        sectionid = thissection[:sec].to_s
        sectionqid = sectionid.gsub(/.*\#/, "") # remove everything up to the hash in the URL
        _sectionlabel = thissection[:label]
        warn "secid #{sectionid}"
        warn "qid #{sectionqid}"

        sparql_results = get_section_questions_query(sectionid: sectionqid) 
        @data = {} # Internal storage: key by ?q for uniqueness

        # TODO  Note that this only allows one Fieldset per dataset!  Not like the Duchenne app...
        # fields is reset here to [], so any other fieldset is overwritten...
        @fields = [] # Array of field metadata, sorted by ?sequence

        # Process SPARQL results (array of hashes)
        sparql_results.each do |result|
          q = result[:q].to_s  # "https://w3id.org/CBGP-App#tis123"
          questionclass = result[:q].to_s.match(%r{.*?#(\S+)$})[1]   # "tis123"
          # TODO  creating a symbol for methodname now might be a problem??!!
          method_name = result[:method].to_s.to_sym # e.g., :surname
          klass = result[:class].to_s.downcase # e.g., 'string'
          cardinality = result[:cardinality].to_s # 'multi' or 'single'
          answers_uri = result[:answers].to_s # URI for possible answers (stubbed fetch below)
          sequence = result[:sequence].to_s.to_i
          is_primary = result[:primary].to_s || "false"

          # Store metadata, sorted later
          @fields << { q: q, questionclass: questionclass, label: result[:label].to_s, 
                      widget: result[:widget].to_s.downcase, method: method_name,
                      class: klass, cardinality: cardinality, answers: answers_uri, 
                      is_primary: is_primary, sequence: sequence }

          # Initialize internal data
          @data[q] = (cardinality == 'multi' ? [] : nil)

          # Metaprogram getter
          define_singleton_method(method_name) do
            @data[q]
          end

          # Metaprogram setter with type coercion and basic validation
          define_singleton_method("#{method_name}=") do |value|
            coerced_value = coerce_value(value, klass, cardinality)
            validate_value(coerced_value, fetch_answers(answers_uri)) if answers_uri

            if cardinality == 'multi'
              if value.is_a?(Array)
                @data[q] = coerced_value # Replace array
              else
                @data[q] << coerced_value # Append single value
              end
            else
              @data[q] = coerced_value
            end
          end
        end
      end

      # Sort fields by sequence for UI/display order
      @fields.sort_by! { |f| f[:sequence] }
    end

    # Helper: Coerce value to type (extend as needed)
    def coerce_value(value, klass, _cardinality)
      case klass
      when 'string'
        value.to_s
      when 'integer'
        value.to_i
      when 'date'
        Date.parse(value.to_s)
      # Add more types: float, boolean, etc.
      else
        value # Fallback: no coercion
      end
    rescue StandardError => e
      raise ArgumentError, "Invalid value #{value} for type #{klass}: #{e.message}"
    end

    # Stub: Fetch possible answers from KB (replace with real SPARQL query to ?answers URI)
    def fetch_answers(_answers_uri)
      # Example: Query KB for list of allowed values
      # return sparql_client.query("SELECT ?answer WHERE { <#{answers_uri}> :hasAnswer ?answer }").map { |r| r[:answer] }
      [] # Stub: empty means no validation
    end

    # Basic validation (extend with custom rules)
    def validate_value(value, allowed_answers)
      return if allowed_answers.empty?

      if value.is_a?(Array)
        unless value.all? { |v| allowed_answers.include?(v) }
          raise ArgumentError, "Value #{value} must be one of #{allowed_answers}"
        end
      else
        raise ArgumentError, "Value #{value} must be one of #{allowed_answers}" unless allowed_answers.include?(value)
      end
    end

    def self.load_from_params(params:)
      warn "PARAMS"
      warn "#{params.inspect}"
      oldgraphid = params["primary_id"]
      # abort "breaking here"
#       PARAMS
# {"mem_primary_id"=> "8347820934957453", "mem1"=>"qwerew", "mem2"=>"qwerqwer", "mem3"=>"4352345", "mem4"=>"3455", "mem5"=>"", 
#  "mem6"=>"qwrqew@twqtr", "mem7"=>"werqewr@asdgfasdf", "mem9"=>"", "mem10"=>"", "mem11"=>"3241234-123123", 
# "permanence"=>"permanent_yes", "int_project_code"=>"23432234", "ext_project_reference"=>"", 
# "call_reference"=>"", "member_institution"=>"members_fgupm", "gender"=>"male", "nationality"=>"norway", 
# "research-area_group"=>"synthetic-biology_bioengineering", "member_team_leader"=>"team_leader_yes", 
# "group_institution"=>"UPM", "database"=>"add-member"}


#  select ?g where {graph ?g {?pub sio:SIO_000671 ?id . ?id  sio:SIO_000300 "#{doi}" ;
      dataset = CBGP::Parsers.params_parser_dataset(params: params)  # returns CBGP::Dataset' mimght overwrite primary_id
      
      # what is the equivalent ID lookup here?
      # TODO this afternoon!
      res = retrieve_dataset_graph_query(primary_id: dataset.primary_id)
      oldgraphid = res.first[:g].to_s if res.first
      CBGP::Dataset.write_to_db(dataset: dataset, oldid: oldgraphid)  # oldid is deleted
      dataset
    end

    def self.write_to_db(dataset:, oldid: nil)
      warn 'WRITING DATASET TO DB'
      write_dataset_to_db(dataset: dataset, oldid: oldid)
    end

    def self.get_questionnaire_fields(questionnaire_type:)
      questionnaire = generate_questionnaire(questionnaire_type: questionnaire_type)
      fields = []
      questionnaire.sections.each do |section|
        section.questions.each do |question|
          # :questionid, :sequence, :objectclass, :objectmethod, :ablockid, :answertree, :question, :selected_answer,
          #      :widget, :cardinality, :answerblock
          fields << {
            fieldid: question.questionid,  # this is the ontological class of tjhe question
            label: question.question,
            objectmethod: question.objectmethod,
            objectclass: question.objectclass,
            widget: question.widget,
            answerblockid: question.ablockid
          }
        end
      end
      fields.sort_by { |f| f[:fieldid] } # Sort for consistent column order
    end


  end
end
