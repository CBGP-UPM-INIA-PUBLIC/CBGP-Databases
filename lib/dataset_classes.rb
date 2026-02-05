require_relative 'queries'
require_relative 'core'
require 'uuidtools'

module CBGP
  class Dataset
    attr_accessor :fields, :form_type, :primary_id

    @@fields_cache = {} # OPTIMIZATION: Class-level cache for fields per type
    @@methods_defined = {} # OPTIMIZATION: Track if getters/setters are defined per type to avoid re-definition

    def initialize(type:, primary_id: nil)
      @form_type = type
      @primary_id = primary_id
      @data = {}

      # OPTIMIZATION: Use cached fields instead of re-querying sections/questions
      @fields = self.class.get_questionnaire_fields(questionnaire_type: type)

      # OPTIMIZATION: Define methods only once per type (class-level, shared across instances)
      return if @@methods_defined[type]

      @fields.each do |field|
        q = field[:q] || "field_#{field[:fieldid]}" # Fallback if :q missing; adjust if needed
        method_name = field[:method]
        klass = field[:class]
        cardinality = field[:cardinality]
        answers_uri = field[:answers]

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
      @@methods_defined[type] = true
    end

    def coerce_value(value, klass, cardinality)
      klass.downcase!
      return '' if value.to_s.strip.empty?

      if cardinality.downcase == 'multiple' && value.is_a?(Array)
        value.map { |v| v.to_s.strip }.reject(&:empty?)
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

    def self.load_from_graph(graph:, database:, pre_fetched_details: nil)
      dataset = new(type: database)

      # OPTIMIZATION: Use batched details if provided, else fallback to single fetch
      details = pre_fetched_details || fetch_dataset_raw_data(graphuri: graph, database: database)

      primary_id = retrieve_dataset_id_from_graph_query(graph: graph)
      abort "Load From Graph- can't retrieve primary id for graph #{graph}" unless primary_id
      dataset.primary_id = primary_id

      dataset.fields.each do |field|
        value = details[field[:questionclass].to_sym]
        dataset.public_send("#{field[:method]}=", value) if value
      end

      dataset
    end

    def self.load_from_primary_id(primary_id:, database:) # this is always the INTERNAL primaryid, not an external (e.g. not a DOI)
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

    # data has been entered into the HTML form, or a loader. Here we are validating it
    def self.load_from_params_and_write(params:)
      warn "PARAMS: #{params.inspect}"
      # Create the instance – NO auto-generation of primary_id in initialize anymore
      # primary_id starts as nil
      dataset = CBGP::Dataset.new(type: params['database'])

      dataset.fields.each do |field|
        value = params[field[:questionclass]] # get the submitted value from incoming FORM parameters
        next unless value
        next if value.empty?

        warn "field #{field[:label]} value #{value}"

        if field[:is_external_primary].downcase == 'true' # filter for an existing record that has this external primary identifier
          # set the current primary_id to the primary_id of that record if it exists.
          # # this will trigger an overwrite, rather than a duplication of that record
          dataset.primary_id = CBGP::Dataset.get_primary_id(questionclass: field[:questionclass], questionvalue: value,
                                                            dataset_type: params['database'])
          warn "set primaryid to #{dataset.primary_id.inspect}"
          # can return nil if there is no existing record, and a new primary_id will be generated later
        end

        coerced_value = dataset.coerce_value(value, field[:class], field[:cardinality])
        if coerced_value && (!coerced_value.is_a?(Array) || !coerced_value.empty?)
          dataset.public_send("#{field[:method]}=",
                              coerced_value)
        end
      end

      # ensure a primary_id exists at this point, from any source
      # - If params include a primary_id (hidden field from edit form) → reuse it (update existing graph)
      # - If params include an external primary identifier, then the earlier query will have set the dataset.primary_id already
      # - Otherwise (new record) → generate a fresh UUID now
      primary_id_param = params['primary_id'].to_s.strip
      dataset.primary_id = if dataset.primary_id && dataset.primary_id.empty? # if it has already been set, then this takes precedence
                             if primary_id_param.empty?
                               SecureRandom.uuid # Fresh ID for new records
                             else
                               primary_id_param # Reuse imcoming ID for updates
                             end
                           else
                             dataset.primary_id # just return existing id
                           end
      dataset.write_to_db
      dataset
    end

    def self.get_primary_id(questionclass:, questionvalue:, dataset_type:)
      graphuris = execute_search(search_params: { questionclass => questionvalue }, dataset_type: dataset_type) # execute_search(search_params:, dataset_type:)
      warn "Found GraphURIs #{graphuris.inspect}"
      unless graphuris.empty?
        res = retrieve_dataset_id_from_graph_query(graph: graphuris.first) # comes back as a string
        return res
      end
      nil # keeps it empty for the main routine to set it later
    end

    def write_to_db
      warn 'WRITING DATASET TO DB'
      self.primary_id = SecureRandom.uuid unless primary_id
      write_dataset_to_db(dataset: self)
    end

    def self.write_to_db(dataset:, oldid: nil)
      # TODO: Should check... probably an existing primary_id should be made the old id for deletion??  think about this
      warn 'WRITING DATASET TO DB'
      dataset.primary_id = SecureRandom.uuid if dataset.primary_id.empty?
      write_dataset_to_db(dataset: dataset, oldid: oldid)
    end

    def self.get_questionnaire_fields(questionnaire_type:)
      @@fields_cache[questionnaire_type] ||= begin # OPTIMIZATION: Compute once from cached Questionnaire
        questionnaire = Questionnaire.get_cached(questionnaire_type: questionnaire_type)
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

    # use labels for display of currently selected hiearrchical tree node
    def self.find_label_by_id(nodes, target_id)
      nodes.each do |node|
        return node['text'] if node['id'] == target_id

        if node['children']&.any?
          found = find_label_by_id(node['children'], target_id)
          return found if found
        end
      end
      nil
    end

    # Flatten tree with paths for search suggestions
    def self.flatten_with_path(nodes, path = [], result = [])
      nodes.each do |node|
        current_path = path + [node['text']]
        result << { id: node['id'], label: current_path.join(' → ') }
        flatten_with_path(node['children'] || [], current_path, result) if node['children']
      end
      result
    end
  end
end
