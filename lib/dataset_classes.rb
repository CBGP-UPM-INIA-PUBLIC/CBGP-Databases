require_relative 'queries'
require_relative 'core'
require 'uuidtools'

module CBGP
  class Dataset
    attr_accessor :fields, :form_type, :primary_id, :id

    def initialize(type:, primary_id: nil)
      @form_type = type
      @primary_id = primary_id #  SecureRandom.uuid
      sections = get_questionnaire_sections_query(questionnaire_type: type)
      @data = {}
      @fields = []

      sections.each do |thissection|
        sectionid = thissection[:sec].to_s
        sectionqid = sectionid.gsub(/.*\#/, '')
        _sectionlabel = thissection[:label]
        warn "secid #{sectionid}"
        warn "qid #{sectionqid}"

        sparql_results = get_section_questions_query(sectionid: sectionqid)

        sparql_results.each do |result|
          q = result[:q].to_s
          questionclass = result[:q].to_s.match(/.*?#(\S+)$/)[1]
          method_name = result[:method].to_s.to_sym
          klass = result[:class].to_s.downcase
          cardinality = result[:cardinality].to_s
          answers_uri = result[:answers].to_s
          sequence = result[:sequence].to_s.to_i
          is_primary = result[:primary].to_s || 'false'

          @fields << { q: q, questionclass: questionclass, label: result[:label].to_s,
                       widget: result[:widget].to_s.downcase, method: method_name,
                       class: klass, cardinality: cardinality, answers: answers_uri,
                       is_primary: is_primary, sequence: sequence }

          @data[q] = (cardinality == 'Multiple' ? [] : nil)

          define_singleton_method(method_name) do
            @data[q]
          end

          define_singleton_method("#{method_name}=") do |value|
            coerced_value = coerce_value(value, klass, cardinality)
            validate_value(coerced_value, fetch_answers(answers_uri)) if answers_uri && !answers_uri.end_with?('#FREE')
            @data[q] = coerced_value
          end
        end
      end

      @fields.sort_by! { |f| f[:sequence] }
    end

    def coerce_value(value, klass, cardinality)
      if cardinality == 'Multiple' && value.is_a?(Array)
        value.map { |v| v.to_s.strip }.reject { |v| v.empty? }
      else
        case klass
        when 'string'
          value.to_s.strip
        when 'integer'
          value.to_i
        when 'date'
          Date.parse(value.to_s).strftime('%Y-%m-%d')
        else
          value.to_s.strip
        end
      end
    rescue StandardError => e
      raise ArgumentError, "Invalid value #{value} for type #{klass}: #{e.message}"
    end

    def fetch_answers(answers_uri)
      [] # Stub: replace with SPARQL query if needed
    end

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

    # data has been entered into the HTML form.  Here we are validating it
    def self.load_from_params_and_write(params:)
      warn "PARAMS: #{params.inspect}"
      # Create the instance – NO auto-generation of primary_id in initialize anymore
      # primary_id starts as nil
      dataset = CBGP::Dataset.new(type: params['database'])

      # ensure a primary_id exists
      # - If params include a primary_id (hidden field from edit form) → reuse it (update existing graph)
      # - Otherwise (new record) → generate a fresh UUID now
      primary_id_param = params['primary_id'].to_s.strip
      dataset.primary_id = if primary_id_param.empty?
                             SecureRandom.uuid # Fresh ID for new records
                           else
                             primary_id_param # Reuse existing ID for updates
                           end

      dataset.fields.each do |field|
        value = params[field[:questionclass]]
        next unless value

        coerced_value = dataset.coerce_value(value, field[:class], field[:cardinality])
        if coerced_value && (!coerced_value.is_a?(Array) || !coerced_value.empty?)
          dataset.public_send("#{field[:method]}=",
                              coerced_value)
        end
      end
      dataset.write_to_db
      dataset
    end

    def self.load_from_graph(graph:, database:)
      dataset = new(type: database)

      # graphuri = res.first[:g].to_s  # comes back as sparql result
      warn "\n\nLOAD FROM GRAPHURI FOUND GRAPH #{graph}\n\n"
      res = retrieve_dataset_id_from_graph_query(graph: graph) # comes back as a sparql query result
      abort "lookup of graph #{graph} failed" unless res&.first
      primary_id = res.first[:id].to_s
      abort "can't retrieve primary id for graph #{graph}" if primary_id.empty?
      dataset.primary_id = primary_id
      details = fetch_dataset_raw_data(graphuri: graph, database: database)
      dataset.fields.each do |field| # dataset is a CBGP::Dataset object that is empty
        value = details[field[:questionclass].to_sym] # get the value for this field
        # metaprogramming set value for the associated object method
        dataset.public_send("#{field[:method]}=", value) if value # Load up the Dataset object
      end
      dataset
    end

    def self.load_from_primary_id(primary_id:, database:)
      dataset = new(type: database)
      abort 'primary id cannot be empty - load from identifier ' if primary_id.empty?
      dataset.primary_id = primary_id
      graphuri = retrieve_dataset_graph_query(primary_id: primary_id) # returns sparql results
      abort "can't load record with primary id #{primary_id}" unless graphuri
      graphuri = graphuri.first[:g].to_s # it's a sparql result

      warn "\n\nLOAD FROM GRAPHURI FOUND GRAPH #{graphuri}\n\n"
      details = fetch_dataset_raw_data(graphuri: graphuri, database: database)
      dataset.fields.each do |field| # dataset is a CBGP::Dataset object that is empty
        value = details[field[:questionclass].to_sym] # get the value for this field
        # metaprogramming set value for the associated object method
        dataset.public_send("#{field[:method]}=", value) if value # Load up the Dataset object
      end
      dataset
    end

    def write_to_db
      warn 'WRITING DATASET TO DB'
      write_dataset_to_db(dataset: self, oldid: primary_id)
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
          fields << {
            fieldid: question.questionid,
            label: question.question,
            objectmethod: question.objectmethod,
            objectclass: question.objectclass,
            widget: question.widget,
            answerblockid: question.ablockid,
            cardinality: question.cardinality,
            sequence: question.sequence
          }
        end
      end
      fields.sort_by { |f| f[:sequence] }
    end
  end
end
