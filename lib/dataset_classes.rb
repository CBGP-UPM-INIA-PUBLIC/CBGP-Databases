require_relative 'queries'
require_relative 'core'
require 'uuidtools'

module CBGP
  class Dataset
    attr_accessor :fields, :form_type, :primary_id

    @@fields_cache = {} # OPTIMIZATION: Cache exact original @fields per type
    @@methods_defined = {} # OPTIMIZATION: Track if dynamic methods defined per type

    def self.fields_for(type)
      lang = current_language
      key = "#{type}_#{lang}"
      warn "[CACHE] Checking fields_for(#{type.inspect}) → key=#{key.inspect}, current lang=#{lang.inspect}, thread=#{Thread.current.object_id}"

      if @@fields_cache[key]
        warn "[CACHE] HIT for #{key}"
        warn "[CACHE] HIT value #{@@fields_cache[key]}"
        return @@fields_cache[key]
      end

      warn "[CACHE] MISS → building for #{key}"
      @@fields_cache[key] ||= begin
        fields = []
        sections = get_questionnaire_sections_query(questionnaire_type: type)
        sections.each do |thissection|
          sectionid = thissection[:sec].to_s
          sectionqid = sectionid.gsub(/.*\#/, '')
          sectionlabel = thissection[:label]

          sparql_results = get_section_questions_query(sectionid: sectionqid)
          sparql_results.each do |result|
            q = result[:q].to_s # full URI
            questionclass = q.match(/.*?#(\S+)$/)[1] # fragment
            method_name = result[:method]&.to_s&.to_sym # symbol, safe if nil
            klass = result[:class]&.to_s&.downcase || 'string' # fallback
            cardinality = result[:cardinality].to_s
            answers_uri = result[:answers].to_s
            sequence = result[:sequence].to_i
            is_external_primary = result[:primary]&.to_s || 'false'

            fields << {
              q: q,
              questionclass: questionclass,
              label: result[:label].to_s,
              widget: result[:widget].to_s.downcase,
              method: method_name,
              class: klass,
              cardinality: cardinality,
              answers: answers_uri,
              is_external_primary: is_external_primary,
              sequence: sequence,
              sectionid: sectionid,
              sectionlabel: sectionlabel
            }
          end
        end
        fields.sort_by! { |f| f[:sequence] }
        fields
      end
      @@fields_cache[key]
    end

    def initialize(type:, primary_id: nil)
      @form_type = type
      @primary_id = primary_id
      @data = {}

      # Use cached exact fields (heavy lifting done once per type)
      @fields = self.class.fields_for(type)

      # Initialize storage hash
      @fields.each do |field|
        @data[field[:q]] = (field[:cardinality] == 'Multiple' ? [] : nil)
      end

      # Define getters/setters per-instance (fast, reliable)
      @fields.each do |field|
        method_name = field[:method]
        next if method_name.nil? || method_name.to_s.empty? # Guard (with optional debug warn below)

        # Optional debug: warn "Skipping method definition for #{field[:questionclass]} (no :method)" if method_name.nil?

        q = field[:q]
        klass = field[:class]
        cardinality = field[:cardinality]
        answers_uri = field[:answers]

        define_singleton_method(method_name) do
          @data[q]
        end

        define_singleton_method("#{method_name}=") do |value|
          coerced_value = coerce_value(value, klass, cardinality)
          if answers_uri && !answers_uri.end_with?('#FREE')
            validate_value(coerced_value,
                           fetch_answers(answers_uri))
          end
          @data[q] = coerced_value
        end
      end
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

    def self.load_from_primary_id(primary_id:, database:)
      dataset = new(type: database)
      abort 'primary id cannot be empty - load from identifier ' if primary_id.empty?
      dataset.primary_id = primary_id

      graphuri_results = retrieve_dataset_graph_query(primary_id: primary_id)
      abort "can't load record with primary id #{primary_id}" unless graphuri_results && graphuri_results.any?

      graphuri = graphuri_results.first[:g].to_s

      # FIX: Handle new array return from fetch_datasets_raw_data
      details_array = fetch_datasets_raw_data(graph_uris: [graphuri], database: database)
      details = details_array.first || { dataset: graphuri }

      dataset.fields.each do |field|
        next unless field[:method]

        value = details[field[:questionclass].to_sym]
        dataset.public_send("#{field[:method]}=", value) if value
      end

      dataset
    end

    # If you have a similar single fallback in load_from_graph (the pre_fetched_details nil case)
    def self.load_from_graph(graph:, database:, pre_fetched_details: nil, pre_fetched_primary_id: nil)
      dataset = new(type: database)

      primary_id = pre_fetched_primary_id || retrieve_dataset_id_from_graph_query(graph: graph)
      abort "Can't retrieve primary id for graph #{graph}" unless primary_id
      dataset.primary_id = primary_id

      # FIX: Handle new array return
      if pre_fetched_details
        details = pre_fetched_details # Already single hash from batch
      else
        details_array = fetch_datasets_raw_data(graph_uris: [graph], database: database)
        details = details_array.first || { dataset: graph }
      end

      dataset.fields.each do |field|
        next unless field[:method]

        value = details[field[:questionclass].to_sym]
        dataset.public_send("#{field[:method]}=", value) if value
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
