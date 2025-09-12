require_relative 'queries'
require_relative 'core'

module CBGP
  # class Member
  #   attr_accessor :uniqid, :surnames, :names, :honorific, :upmid, :nationality, :position, :grupo

  #   def initialize(surnames: '', names: '', honorific: '', upmid: '', grupo: '', nationality: '', position: '')
  #     @uniqid = Time.now.to_i unless uniqid.match(/S/)
  #     @surnames = surnames
  #     @names = names
  #     @honorific = honorific
  #     @nationality = nationality
  #     @position = position
  #     @upmid = upmid
  #     @grupo = grupo
  #   end

  # end
  class Dataset
    attr_reader :fields # Expose sorted fields for UI ordering

    def initialize(type:)  # passed database type e.g. add_members
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
        @fields = [] # Array of field metadata, sorted by ?sequence

        # Process SPARQL results (array of hashes)
        sparql_results.each do |result|
          q = result[:q]
          method_name = result[:method].to_s.to_sym # e.g., :surname
          klass = result[:class].to_s.downcase # e.g., 'string'
          cardinality = result[:cardinality].to_s # 'multi' or 'single'
          answers_uri = result[:answers].to_s # URI for possible answers (stubbed fetch below)
          sequence = result[:sequence].to_s.to_i

          # Store metadata, sorted later
          @fields << { q: q, label: result[:label].to_s, widget: result[:widget].to_s, method: method_name,
                      class: klass, cardinality: cardinality, answers: answers_uri, sequence: sequence }

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
  end
end
