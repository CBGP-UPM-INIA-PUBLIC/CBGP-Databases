require_relative 'queries'
require_relative 'core'
require 'uuidtools'

module CBGP
  # Represents a single database record of any form type (member, project,
  # publication, …).
  #
  # Each Dataset maps to one named graph in the triple store.  The graph URI
  # follows the pattern:
  #   #{BASE_URI}<form_type>/context/<primary_id>
  #
  # Field definitions are read from the OWL ontology at runtime via SPARQL and
  # cached per (form_type, language) pair.  For each field, a pair of singleton
  # getter/setter methods is defined on the instance so that field values can be
  # accessed by the Ruby method name declared in the ontology (+local:method+).
  #
  # == Cross-reference fields
  # Fields that link to records in another form carry three extra ontology
  # properties (+local:references+, +local:references-via+,
  # +local:references-label+) which drive the typeahead widget in the GUI.
  # The stored value is whatever +references-via+ points to (e.g. an ORCiD),
  # while the typeahead searches and displays using +references-label+ (e.g. a
  # surname).
  #
  # @attr [Array<Hash>] fields field descriptors loaded from the ontology
  # @attr [String] form_type  ontology class fragment identifying this form
  #   (e.g. +"member"+, +"project"+)
  # @attr [String, nil] primary_id  UUID identifying this record; nil until set
  # rubocop:disable Metrics/ClassLength
  class Dataset
    attr_accessor :fields, :form_type, :primary_id

    @@fields_cache       = {}  # keyed by "form_type_lang"; avoids re-querying the ontology
    @@methods_defined    = {}  # guards against redefining singleton methods per type
    @@primary_key_cache  = {}  # caches the is-primary-id method name per form type

    # Returns the array of field descriptor hashes for a given form type,
    # building and caching it on first call per (type, language) pair.
    #
    # Each hash contains: +:q+, +:questionclass+, +:label+, +:widget+,
    # +:method+, +:class+, +:cardinality+, +:answers+, +:is_external_primary+,
    # +:sequence+, +:sectionid+, +:sectionlabel+, +:references+,
    # +:references_target+, +:references_via+, +:references_via_method+.
    #
    # @param type [String] ontology form fragment, e.g. +"member"+
    # @return [Array<Hash>] field descriptors sorted by +:sequence+
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
            references = result[:references]&.to_s # full URI if present
            references_target = result[:references] ? result[:references].to_s.split('#').last : nil # e.g. "member"
            references_via = result[:references_via]&.to_s # e.g. "orcid"   (method name in target)
            references_via_method = result[:references_via] ? result[:references_via].to_s.split('#').last : nil # e.g. "orcid"

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
              sectionlabel: sectionlabel,
              references: references, # full URI of the FOrm (e.g. w3id.org/CBGP-App#member)
              references_target: references_target, # just #form
              references_via: references_via,
              references_via_method: references_via_method
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
        @data[field[:q]] = (field[:cardinality].downcase == 'multiple' ? [] : nil)
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

          # Standard controlled-vocabulary validation (unchanged)
          validate_value(coerced_value, fetch_answers(answers_uri)) if answers_uri && !answers_uri.end_with?('#FREE')

          # New: generic reference validation
          validate_references(field, coerced_value) if field[:references_target_form]

          @data[q] = coerced_value
        end

        # Optional helpers — only define if it's a reference field (once per field, not per setter call!)
        next unless field[:references_target_form]

        # Helper: returns target form name e.g. "member"
        define_singleton_method("#{method_name}_target_form") do
          field[:references_target_form]
        end

        # Helper: returns the resolved key method name in the target form (computed once)
        define_singleton_method("#{method_name}_key_method") do
          via_class = field[:references_via_class]
          if via_class
            self.class.resolve_key_method(field[:references_target_form], via_class)
          else
            self.class.key_method_for_form(field[:references_target_form])
          end
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

    def validate_references(field, value)
      target_form = field[:references_target_form]
      return unless target_form # clearer guard

      # Prefer via_class → method resolution; fallback to primary field of target form
      key_method = if field[:references_via_class]
                     self.class.resolve_key_method(target_form, field[:references_via_class])
                   else
                     self.class.key_method_for_form(target_form)
                   end

      return unless key_method # silent skip if no key found (or raise/warn)

      Array(value).each do |v|
        next if v.to_s.strip.empty?

        found_primary_id = CBGP::Dataset.get_primary_id(
          questionclass: key_method,
          questionvalue: v.strip,
          dataset_type: target_form
        )

        unless found_primary_id
          warn "[FOREIGN-KEY] No #{target_form} found matching #{key_method} = '#{v}'"
          # raise ArgumentError, "..." if you later want strict enforcement
        end
      end
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

    # Builds a list of typeahead suggestions for a cross-reference field.
    #
    # This method powers the +/cbgp/reference/suggest/:target+ endpoint and
    # supports two distinct modes:
    #
    # * *Standard* (+via_class+ absent): the displayed label and the stored
    #   value are the same field (e.g. an email address field that also serves
    #   as the cross-reference key).
    #
    # * *Cross-reference* (+via_class+ present): the user searches and sees one
    #   field (e.g. surname, controlled by +label_method+) but the value that
    #   gets stored is a different field (e.g. ORCiD, controlled by +via_class+).
    #   Both +via_class+ and +label_method+ are questionclass fragments; they are
    #   resolved to Ruby method names via +resolve_key_method+ before being used
    #   with +public_send+.  The questionclass itself is used unmodified as the
    #   SPARQL search predicate.
    #
    # @param target_form  [String]       form type to search, e.g. +"member"+
    # @param limit        [Integer]      maximum number of suggestions to return
    # @param search_query [String, nil]  partial text from the user; +nil+ or
    #   blank returns up to +limit+ records (broad search)
    # @param via_class    [String, nil]  questionclass of the field whose value
    #   is stored (e.g. +"member_orcid"+); nil means value == label
    # @param label_method [String, nil]  questionclass of the field shown in the
    #   typeahead dropdown (e.g. +"member_surnames"+); falls back to +via_class+
    #   field when nil
    # @return [Array<Hash>] array of +{ value:, label: }+ hashes ready for JSON
    #   serialisation; +value+ is what gets stored, +label+ is what is displayed
    def self.fetch_reference_suggestions(target_form:, limit: 100,
                                         search_query: nil, via_class: nil,
                                         label_method: nil)
      return [] unless target_form

      key_method = if via_class && !via_class.to_s.strip.empty?
                     resolve_key_method(target_form, via_class)
                   else
                     key_method_for_form(target_form)
                   end
      return [] if key_method.to_s.strip.empty?

      # label_method is a questionclass fragment used for two distinct purposes:
      #   1. SPARQL search key  — used directly as the predicate type in search_params
      #   2. Ruby public_send   — needs the local:method name, which may differ
      # resolve_key_method handles the questionclass → method name translation.
      search_questionclass = label_method.to_s.strip.empty? ? nil : label_method.to_s.strip
      search_method = if search_questionclass
                        resolved = resolve_key_method(target_form, search_questionclass)
                        resolved.to_s.strip.empty? ? key_method : resolved
                      else
                        key_method
                      end

      warn "[SUGGEST] key_method='#{key_method}', search_questionclass='#{search_questionclass}', search_method='#{search_method}' for #{target_form}"

      broad = search_query.nil? || search_query.strip.empty?

      graphs = execute_search(
        search_params: broad ? {} : { (search_questionclass || key_method) => search_query.strip },
        dataset_type: target_form,
        broad: broad
      ).first(limit)

      graphs.map do |graph_uri|
        ds = CBGP::Dataset.load_from_graph(graph: graph_uri, database: target_form)
        next unless ds

        value = begin
          ds.public_send(key_method).to_s.strip
        rescue StandardError
          ds.primary_id.to_s.strip
        end
        next if value.empty?

        label = begin
          ds.public_send(search_method).to_s.strip
        rescue StandardError
          value
        end
        label = value if label.empty?

        { value: value, label: label }
      end.compact
    end

    # Resolves a questionclass fragment to the Ruby method name declared in the
    # ontology via +local:method+.
    #
    # This is necessary because the questionclass (used as the SPARQL predicate
    # type, e.g. +"member_orcid"+) and the Ruby method name (used with
    # +public_send+, e.g. +"orcid"+) can differ.  The ontology is the single
    # source of truth for the mapping.
    #
    # Used for both the stored-value field (+via_class+) and the display/search
    # field (+label_method+) in cross-reference typeaheads.
    #
    # @param target_form_fragment [String] form type, e.g. +"member"+ (currently
    #   unused in the query but kept for future scoping)
    # @param via_class_fragment [String] questionclass fragment, e.g.
    #   +"member_orcid"+
    # @return [String, nil] the +local:method+ value, or +nil+ if not found
    def self.resolve_key_method(target_form_fragment, via_class_fragment)
      query = <<~SPARQL
        #{PREFIXES}
        SELECT ?method
        WHERE {
          cbgp:#{via_class_fragment} local:method ?method .
        }
      SPARQL
      results = SPARQL.parse(query).execute($ontology)
      method_name = results.first[:method]&.to_s
      warn "[RESOLVE KEY] For #{target_form_fragment} via #{via_class_fragment} → #{method_name.inspect}"
      method_name
    end

    # Returns the Ruby method name for the field in +form_type+ that is marked
    # +local:is-primary-id true+ in the ontology.  Result is memoised per form
    # type.
    #
    # The primary-id field is the one whose value uniquely identifies a record
    # for external cross-reference lookups (e.g. ORCiD for members).
    #
    # @param form_type [String] ontology form fragment, e.g. +"member"+
    # @return [String, nil] the method name, or +nil+ if no primary field is
    #   declared
    def self.key_method_for_form(form_type)
      @@primary_key_cache[form_type] ||= begin
        sections = get_questionnaire_sections_query(questionnaire_type: form_type)
        sections.each do |sec|
          results = get_section_questions_query(sectionid: sec[:sec].fragment)
          results.each do |res|
            return res[:method].to_s if res[:primary].to_s.downcase == 'true'
          end
        end
        nil
      end
    end

    # Loads a Dataset by its primary_id string, searching across all graphs.
    #
    # @param primary_id [String] the record's primary identifier value
    # @param database   [String] form type, e.g. +"member"+
    # @return [CBGP::Dataset] populated dataset instance
    # @raise [SystemExit] if primary_id is blank or no graph is found
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

    # Loads a Dataset from a known named graph URI.
    #
    # Accepts pre-fetched data to avoid redundant SPARQL round-trips when
    # called in a batch context (e.g. from +fetch_datasets_raw_data+).
    #
    # @param graph                 [String]     full named graph URI
    # @param database              [String]     form type, e.g. +"member"+
    # @param pre_fetched_details   [Hash, nil]  already-retrieved field hash
    #   keyed by questionclass symbol; re-fetched if nil
    # @param pre_fetched_primary_id [String, nil] already-retrieved primary_id;
    #   queried from the graph if nil
    # @return [CBGP::Dataset] populated dataset instance
    # @raise [SystemExit] if the primary_id cannot be determined
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

    # Validates incoming form parameters, writes the dataset, and returns it.
    #
    # This is the single entry point for all HTML form submissions and bulk
    # loaders.  It handles both *new record* and *edit* paths:
    #
    # * *New record*: the form's hidden +primary_id+ field is empty; a fresh
    #   UUID is generated.
    # * *Edit*: the hidden +primary_id+ field carries the existing UUID; the old
    #   named graph is dropped and rewritten with the same UUID, preserving the
    #   graph URI across edits.
    # * *External primary key*: if a field is marked +local:is-primary-id true+
    #   in the ontology, its submitted value is used to look up an existing
    #   record.  If found, that record's UUID becomes the primary_id (triggering
    #   an overwrite rather than a duplicate).
    #
    # primary_id resolution priority:
    #   1. +is_external_primary+ lookup (highest — set during field iteration)
    #   2. Hidden +primary_id+ form param (edit path)
    #   3. Fresh +SecureRandom.uuid+ (new record)
    #
    # @param params [Hash] Sinatra params hash from the POST request; must
    #   include +'database'+ (form type) and +'primary_id'+ (may be empty)
    # @return [CBGP::Dataset] the saved dataset instance
    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def self.load_from_params_and_write(params:)
      warn "PARAMS: #{params.inspect}"
      dataset = CBGP::Dataset.new(type: params['database'])

      dataset.fields.each do |field|
        value = params[field[:questionclass]]
        next unless value
        next if value.empty?

        warn "field #{field[:label]} value #{value}"

        if field[:is_external_primary].downcase == 'true'
          # Look up any existing record with this external identifier so we
          # overwrite it rather than create a duplicate.
          dataset.primary_id = CBGP::Dataset.get_primary_id(questionclass: field[:questionclass], questionvalue: value,
                                                            dataset_type: params['database'])
          warn "set primaryid to #{dataset.primary_id.inspect}"
        end

        coerced_value = dataset.coerce_value(value, field[:class], field[:cardinality])
        if coerced_value && (!coerced_value.is_a?(Array) || !coerced_value.empty?)
          dataset.public_send("#{field[:method]}=", coerced_value)
        end
      end

      primary_id_param = params['primary_id'].to_s.strip

      if dataset.primary_id.to_s.strip.empty?
        dataset.primary_id = primary_id_param.empty? ? SecureRandom.uuid : primary_id_param
      end

      oldid = primary_id_param.empty? ? nil : primary_id_param
      write_dataset_to_db(dataset: dataset, oldid: oldid)
      dataset
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # Searches for an existing record whose +questionclass+ field has the given
    # value, and returns its primary_id string.
    #
    # Used by +load_from_params_and_write+ to detect duplicates when a field is
    # marked +local:is-primary-id true+ in the ontology (e.g. ORCiD for members).
    #
    # @param questionclass [String] the ontology questionclass to match against
    # @param questionvalue [String] the value to search for
    # @param dataset_type  [String] form type to scope the search
    # @return [String, nil] primary_id of the matching record, or +nil+ if none
    def self.get_primary_id(questionclass:, questionvalue:, dataset_type:)
      graphuris = execute_search(search_params: { questionclass => questionvalue }, dataset_type: dataset_type) # execute_search(search_params:, dataset_type:)
      warn "Found GraphURIs #{graphuris.inspect}"
      unless graphuris.empty?
        res = retrieve_dataset_id_from_graph_query(graph: graphuris.first) # comes back as a string
        return res
      end
      nil # keeps it empty for the main routine to set it later
    end

    # Persists this instance to the triple store, generating a UUID if the
    # record has no primary_id yet.  Always performs a plain INSERT (no delete
    # of a prior graph).  Use +load_from_params_and_write+ for edit semantics.
    #
    # @return [Object] raw response from the SPARQL update endpoint
    def write_to_db
      warn 'WRITING DATASET TO DB'
      self.primary_id = SecureRandom.uuid unless primary_id
      write_dataset_to_db(dataset: self)
    end

    # Class-level write helper.  Delegates to +write_dataset_to_db+ after
    # ensuring a primary_id exists.  Prefer +load_from_params_and_write+ for
    # form submissions, which handles edit/delete semantics correctly.
    #
    # @param dataset [CBGP::Dataset] the dataset to persist
    # @param oldid   [String, nil]   if supplied, the old graph is dropped first
    # @return [Object] raw response from the SPARQL update endpoint
    def self.write_to_db(dataset:, oldid: nil)
      warn 'WRITING DATASET TO DB'
      dataset.primary_id = SecureRandom.uuid if dataset.primary_id.to_s.strip.empty?
      write_dataset_to_db(dataset: dataset, oldid: oldid)
    end

    # Returns a simplified field list derived from a cached +Questionnaire+
    # object.  Used by older code paths that work with the Questionnaire layer
    # rather than the ontology SPARQL layer directly.
    #
    # @param questionnaire_type [String] questionnaire identifier
    # @return [Array<Hash>] field descriptors sorted by +:sequence+
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

    # Recursively searches a jstree-style node array for a node whose +'id'+
    # matches +target_id+ and returns its +'text'+ label.
    #
    # @param nodes     [Array<Hash>] tree nodes with +'id'+, +'text'+, and
    #   optional +'children'+ keys
    # @param target_id [String] the node id to locate
    # @return [String, nil] the node's label, or +nil+ if not found
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

    # Flattens a jstree-style node tree into an array of +{ id:, label: }+
    # hashes where each label is the full ancestor path joined with +' → '+.
    # Used to build search-suggestion text for hierarchical controlled
    # vocabularies (e.g. taxonomy, research area).
    #
    # @param nodes  [Array<Hash>] tree nodes (see +find_label_by_id+)
    # @param path   [Array<String>] ancestor labels accumulated during recursion
    # @param result [Array<Hash>]  accumulator; pass +[]+ on initial call
    # @return [Array<Hash>] flat list of +{ id: String, label: String }+
    def self.flatten_with_path(nodes, path = [], result = [])
      nodes.each do |node|
        current_path = path + [node['text']]
        result << { id: node['id'], label: current_path.join(' → ') }
        flatten_with_path(node['children'] || [], current_path, result) if node['children']
      end
      result
    end
  end
  # rubocop:enable Metrics/ClassLength
end
