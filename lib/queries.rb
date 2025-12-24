# frozen_string_literal: true

require 'linkeddata'
require 'sparql'
require 'sparql/client'
# require 'unicode' # If not already available; Ruby stdlib has String#unicode_normalize, but ensure it's loaded if needed

host = GRAPHDB_HOST || 'localhost:7200'
GRAPHDB_USER || 'cbgp'
GRAPHDB_PASS || 'cbgp'
GRAPHDB_DBNAME || 'kbdatabase'

$ontology = RDF::Repository.load(CBGP_KB) # set in configuration.rb and/or in docker-compose
DATABASE = SPARQL::Client.new("http://#{GRAPHDB_USER}:#{GRAPHDB_PASS}@#{host}/repositories/#{GRAPHDB_DBNAME}")
DATABASE_UPDATE = SPARQL::Client.new("http://#{GRAPHDB_USER}:#{GRAPHDB_PASS}@#{host}/repositories/#{GRAPHDB_DBNAME}/statements")

# List unchanged
ACCENT_SENSITIVE_LABELS = [
  'title',
  'author',
  'authors',
  'affiliation',
  'journal name',
  'partner institutions',
  'research group',
  'research group affiliation'
].freeze

PREFIXES = "PREFIX cbgp: <https://w3id.org/CBGP-App#>
PREFIX owl: <http://www.w3.org/2002/07/owl#>
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX xml:<http://www.w3.org/XML/1998/namespace>
PREFIX xsd:<http://www.w3.org/2001/XMLSchema#>
PREFIX rdfs:<http://www.w3.org/2000/01/rdf-schema#>
PREFIX onto: <http://www.ontotext.com/>
PREFIX sio: <http://semanticscience.org/resource/>
PREFIX schema: <http://schema.org/>
PREFIX edam: <http://edamontology.org/>
PREFIX obo: <http://purl.obolibrary.org/obo/>
PREFIX ncit: <http://purl.obolibrary.org/obo/>
PREFIX local: <urn:local:>
PREFIX dcterms: <http://purl.org/dc/terms/>   # NEW: for provenance timestamps
"

# what database should we be writing to or reading from?
def get_dbname_for_form(form:) # form is e.g. publication or userproject
  # questionnaire_type = Add/Edit publications (#publication) has-fields Publication Questions (#new-publication-questions)
  classname = "cbgp:#{form}"
  qs = <<GET_DBNAME
    #{PREFIXES}

    SELECT ?dbname WHERE {
      #{classname} rdfs:subClassOf cbgp:forms ;
        local:dbname ?dbname .  # this is just the strong, like "project"
    }
GET_DBNAME
  warn "database name query\n\n#{qs}\n\n"
  qs = SPARQL.parse(qs)
  results = qs.execute($ontology)
  results.first[:dbname].to_s
end

def get_questionnaire_types_query(type: 'Core', language: $language) # rubocop:disable Metrics/MethodLength
  # questionnaire_type = Add/Edit publications (#publication) has-fields Publication Questions (#new-publication-questions)

  qs = <<GET_QUESTIONNAIRE_TYPES
    #{PREFIXES}

    SELECT ?questionnaire_type ?questionnaire_label WHERE {
      ?questionnaire_type rdfs:subClassOf cbgp:forms .
      ?questionnaire_type rdfs:label ?questionnaire_label .
      ?questionnaire_type local:form-category "#{type}"@en .  # is this part of the core database or the user-facing forms
      FILTER (lang(?questionnaire_label) = "#{language}")
    }
GET_QUESTIONNAIRE_TYPES
  qs = SPARQL.parse(qs)
  results = qs.execute($ontology)
  results.map { |r| r.to_h.transform_values(&:to_s) } # https://w3id.org/CBGP-App#add-member => "Add/Edit Member"
end

def get_questionnaire_sections_query(questionnaire_type:, language: $language)
  return [] unless questionnaire_type

  # questionnaire_type = Add/Edit publications (#add-publication) has-fields Publication Questions (#new-publication-questions)

  qs = <<GET_QUESTIONNAIRE_SECTIONS
    #{PREFIXES}

    SELECT ?sec (str(?seclab) as ?label) WHERE {
      cbgp:#{questionnaire_type} local:has-fields ?sec . # "publication", "project", "member"
      ?sec rdfs:label ?seclab .
      FILTER (lang(?seclab) = "#{language}")
    }
GET_QUESTIONNAIRE_SECTIONS
  # warn "QUERY IS #{qs}"
  qs = SPARQL.parse(qs)
  qs.execute($ontology)
end

def get_section_questions_query(sectionid:, language: $language)
  qs = <<GET_SECTION_QUESTIONS
    #{PREFIXES}

    SELECT ?q (str(?qlab) as ?label) ?widget ?class ?method ?cardinality ?answers ?primary ?sequence WHERE {
    ?q rdfs:subClassOf cbgp:#{sectionid} .
    ?q rdfs:label ?qlab .
    FILTER (lang(?qlab) = "#{language}")
    ?q local:widget-type ?widget .
    ?q local:widget-cardinality ?cardinality .
    ?q local:answer-block ?answers .
    OPTIONAL {?q local:object-class ?class }.
    ?q local:method ?method .
    OPTIONAL {?q local:is-primary-id ?primary }.
    ?q local:question-order ?sequence .
  } ORDER BY ?sequence

GET_SECTION_QUESTIONS
  qs = SPARQL.parse(qs)
  qs.execute($ontology)
end

def get_answer_block_query(ablockid:, language: $language)
  a = <<GET_ANSWER_BLOCK
    #{PREFIXES}

    SELECT DISTINCT ?aid ?label ?sequence WHERE {
      ?aid rdfs:subClassOf cbgp:#{ablockid} .
      ?aid rdfs:label ?label .
      FILTER (lang(?label) = "#{language}")
      ?aid local:answer-order ?sequence .
    } ORDER BY ?sequence
GET_ANSWER_BLOCK
  # warn "ANSWERBLOCK QUERY IS #{a}"

  a = SPARQL.parse(a)
  a.execute($ontology)
end

def get_hierarchical_answer_block_query(ablockid:, language: $language)
  query = <<~GET_HIERARCHICAL_ANSWERS
    #{PREFIXES}
    SELECT DISTINCT ?aid ?label ?parent ?sequence WHERE {
      ?aid rdfs:subClassOf ?parent .
      ?aid rdfs:label ?label .
      FILTER (lang(?label) = "#{language}")
      OPTIONAL { ?aid local:answer-order ?sequence . }
    } ORDER BY ?sequence
  GET_HIERARCHICAL_ANSWERS

  # warn "HIERARCHICAL ANSWERBLOCK QUERY IS #{query}"
  results = SPARQL.parse(query).execute($ontology)
  tree = build_transitive_tree(results, abblockid: ablockid)
  JSON.generate(tree) # Use JSON.generate for explicit control
end

def get_label_for_questionnaire_type(id:, language: $language)
  lab = SPARQL.parse("
    #{PREFIXES}

    SELECT ?plabel ?label WHERE {
      cbgp:#{id} rdfs:label ?label ;
                 rdfs:subClassOf ?parent .
      ?parent rdfs:label ?plabel
      FILTER (lang(?label) = '#{language}')
      FILTER (lang(?plabel) = '#{language}')
    }
          ")

  res = lab.execute($ontology)
  [res.first[:plabel].to_s, res.first[:label].to_s]
end

def get_label_for_id(id:)
  return nil if id.nil? || id.empty?

  # Strip the document fragment from the URI if it includes a '#'
  id = id.to_s.split('#').last if id.to_s.include?('#')

  query = <<~LABEL_QUERY
    #{PREFIXES}
    SELECT ?label WHERE {
    cbgp:#{id} rdfs:label ?label .
    FILTER (lang(?label) = "en")
    }
    LIMIT 1
  LABEL_QUERY

  warn "LABEL QUERY FOR #{id}: #{query}"
  res = SPARQL.parse(query).execute($ontology)
  if res.any? && res.first&.bound?(:label)
    res.first[:label].to_s
  else
    warn "No label found for id: #{id}"
    id # Fallback to id
  end
end

def field_query(fieldid:, language: $language)
  query = <<~FIELDQ
    #{PREFIXES}
    SELECT ?label ?answerblock ?objectclass ?objectmethod ?questionorder ?cardinality ?widgettype
    WHERE {
        cbgp:#{fieldid} rdfs:label ?label ;
          local:answer-block ?answerblock ;
          local:method ?objectmethod ;
          local:question-order ?questionorder ;
          local:widget-cardinality ?cardinality ;
          local:widget-type ?widgettype .
        FILTER (lang(?label) = '#{language}')
        OPTIONAL {cbgp:#{fieldid} local:object-class ?objectclass .}
    }
  FIELDQ
  # warn "FIELD QUERY is #{query}"
  field = SPARQL.parse(query)
  field.execute($ontology)
end

###################### DATASET ##################
###################### DATASET ##################
###################### DATASET ##################
###################### DATASET ##################
###################### DATASET ##################
###################### DATASET ##################
###################### DATASET ##################
###################### DATASET ##################

def retrieve_dataset_graph_query(primary_id:) # this is prone to collisions, but... one day...
  retds = <<SELECT_DS
        #{PREFIXES}
  select ?g where {
  graph ?g {
      ?dataset sio:SIO_000671 ?id .

      ?id  sio:SIO_000300 "#{primary_id}" ;
        rdf:type sio:SIO_000115 ; # identifier
  }}

SELECT_DS

  warn "retrieve dataset graph query is:\n #{retds}"
  # pubexists = SPARQL.parse(retpub)  # validate query or die
  DATABASE.query(retds)
end

def retrieve_dataset_id_from_graph_query(graph:)
  retds = <<SELECT_DS
        #{PREFIXES}
  select ?id where {
  graph <#{graph}> {
      ?dataset sio:SIO_000671 ?idnode .
      ?idnode  sio:SIO_000300 ?id ;
        rdf:type sio:SIO_000115 ; # identifier
  }}
SELECT_DS

  warn "retrieve dataset id query is:\n #{retds}"
  # pubexists = SPARQL.parse(retpub)  # validate query or die
  DATABASE.query(retds)
end

def delete_dataset_query(oldid:)
  delete = <<DELETE_DATASET
  DROP GRAPH <#{oldid}>

DELETE_DATASET
  DATABASE_UPDATE.update(delete)
end

# Executes a SPARQL UPDATE query to write (insert) a dataset's RDF data into the database.
# If an `oldid` is provided (e.g., when updating an existing dataset), it first deletes
# the old graph containing the previous version of the data.
# Returns the raw response from the database update operation.
def write_dataset_to_db(dataset:, oldid: nil)
  # Build the full INSERT DATA query (with optional preceding DELETE)
  writequery = write_dataset_to_db_query(dataset: dataset, oldid: oldid)

  # Debug: print the query being sent
  warn "WRITE DATASET QUERY\n#{writequery}\n\n\n"

  # Execute the update query against the update-capable endpoint/database
  resp = DATABASE_UPDATE.update(writequery)

  # Debug: print the database response (useful for spotting errors)
  warn "write dataset response #{resp.inspect}"

  resp
end

# Builds the full SPARQL UPDATE query string for inserting a dataset's data.
# The data uses a reified attribute pattern (common in SIO/RDF modelling):
#   - The dataset node has sio:SIO_000008 (has attribute) pointing to a blank-ish node
#   - That attribute node is typed with rdf:type cbgp:<questionclass>
#   - The attribute node has sio:SIO_000300 (has value) with the literal value
# If `oldid` is provided, a DELETE step for the old graph is prepended.
# All values are stored as plain string literals (with proper escaping).
# Updated write_dataset_to_db_query with provenance timestamps
def write_dataset_to_db_query(dataset:, oldid: nil)
  database = dataset.form_type
  primary_id = dataset.primary_id
  warn "WRITE DATASET primary_id is #{primary_id}\n\n"

  delete_dataset_query(oldid: "#{BASE_URI}#{database}/context/#{oldid}") if oldid

  datasetPREFIX         = "<#{BASE_URI}#{database}/dataset/>"
  datasetgraphPREFIX    = "<#{BASE_URI}#{database}/context/>"
  datasetFragmentPREFIX = "<#{BASE_URI}#{database}/dataset/#{primary_id}#>"
  graph_uri             = "#{datasetgraphPREFIX}#{primary_id}" # Full named graph URI (used for provenance)

  # Current UTC timestamp in ISO8601 format (xsd:dateTime compatible literal)
  timestamp = Time.now.utc.iso8601

  triples = []
  # Core typing triples (unchanged)
  triples << "dataset:#{primary_id} rdf:type sio:SIO_000089 ;"
  triples << "   rdf:type cbgp:#{database} ;"
  triples << '   sio:SIO_000671 datasetfrag:primary_id .'
  triples << "   datasetfrag:primary_id sio:SIO_000300 \"#{primary_id}\" ;"
  triples << '           rdf:type sio:SIO_000115 . # identifier.'

  # [Rest of field processing unchanged...]
  dataset.fields.each do |field|
    next unless dataset.respond_to?(field[:method])

    value = dataset.public_send(field[:method])
    next if value.nil? || (value.is_a?(Array) && value.empty?)

    questionclass = field[:questionclass]
    escape_for_literal = ->(v) { v.to_s.gsub('\\', '\\\\').gsub('"', '\\"') }

    if field[:cardinality] == 'Multiple' && value.is_a?(Array)
      value.each_with_index do |val, index|
        next if val.to_s.strip.empty?

        this_attribute = "#{datasetPREFIX.gsub(/[<>]/, '')}#{primary_id}/#{questionclass}_#{index + 1}"
        triples << "dataset:#{primary_id} sio:SIO_000008 <#{this_attribute}> ."
        triples << "<#{this_attribute}> rdf:type cbgp:#{questionclass} ."
        triples << "<#{this_attribute}> sio:SIO_000300 \"#{escape_for_literal.call(val)}\" ."
      end
    else
      this_attribute = "#{datasetPREFIX.gsub(/[<>]/, '')}#{primary_id}/#{questionclass}"
      triples << "dataset:#{primary_id} sio:SIO_000008 <#{this_attribute}> ."
      triples << "<#{this_attribute}> rdf:type cbgp:#{questionclass} ."
      triples << "<#{this_attribute}> sio:SIO_000300 \"#{escape_for_literal.call(value)}\" ."
    end
  end

  body = triples.join("\n")
  # NEW: Provenance timestamps on the graph itself
  # Always add dcterms:modified (last write time)
  prov = "datasetgraph:#{primary_id} dcterms:modified \"#{timestamp}\"^^xsd:dateTime ."

  # If this is a new dataset (no oldid), also add dcterms:created
  prov += "datasetgraph:#{primary_id} dcterms:created \"#{timestamp}\"^^xsd:dateTime ." if oldid.nil?
  # NOTE: On updates (oldid present), we DROP the old graph, so the original created date is lost.
  # This is intentional and simple – created = first seen write, modified = last write.
  # If you need persistent created date across updates, we'd need to fetch it first (more complex).

  <<~WRITE_DATASET
    #{PREFIXES}
    PREFIX dataset: #{datasetPREFIX}
    PREFIX datasetfrag: #{datasetFragmentPREFIX}
    PREFIX datasetgraph: #{datasetgraphPREFIX}
    INSERT DATA { GRAPH datasetgraph:#{primary_id} {
    #{body}
    }
    #{prov}
    }
  WRITE_DATASET
end

#####################################################
######################################################
################    SEARCH   #########################
######################################################
######################################################

# Helper to strip diacritics/accents using Unicode normalization (NFKD decomposition + remove combining marks).
# This turns "ñ" → "n", "é" → "e", etc., for base-letter pattern building.
def unaccent(str)
  str.unicode_normalize(:nfkd).gsub(/[\u0300-\u036f]/, '')
end

# Helper to generate an accent-insensitive regex pattern for search terms.
# First: Unaccent the term to base letters.
# Then: For each base letter, map to a character class including common accented variants.
# Finally: Downcase and escape non-mapped chars.
#
# This allows bidirectional matching: input with/without accents matches stored with/without.
# Example: "briañ" → unaccent → "brian" → pattern "bri[aáàäâã][nñ]"
# Matches: "brian", "briañ", "Brian", etc. (with "i" flag for case-insensitivity).
def accent_insensitive_pattern(term)
  return '' if term.to_s.strip.empty?

  # First, strip accents to get base term
  base_term = unaccent(term).downcase

  # Expanded mapping for Spanish/Latin common accents (add more if needed, e.g., for other languages)
  mapping = {
    'a' => '[aáàäâãåæāăąǎǟǡȁȃȧ]',
    'e' => '[eéèëêēĕėęěȅȇȩ]',
    'i' => '[iíìïîĩīĭįıǐȉȋ]',
    'o' => '[oóòöôõøōŏőǒȍȏȫȭȯ]',
    'u' => '[uúùüûũūŭůűǔȕȗ]',
    'n' => '[nñńņňŉǹ]',
    'c' => '[cçćĉċč]',
    'y' => '[yýÿŷ]' # Added for completeness (e.g., Spanish surnames)
  }

  # Build pattern: replace each base char with its class or escaped
  base_term.gsub(/./) { |char| mapping[char] || Regexp.escape(char) }
end

def build_search_query(search_params:, dataset_type:)
  # [Unchanged early-exit guard]
  return nil unless search_params.is_a?(Hash) &&
                    search_params.any? do |k, v|
                      !v.nil? &&
                      (
                        (!v.is_a?(Hash) && !v.to_s.strip.empty?) ||
                        (v.is_a?(Hash) && v.values.any? { |val| !val.to_s.strip.empty? })
                      )
                    end

  datasetPREFIX = "<#{BASE_URI}#{dataset_type}/dataset/>"
  datasetgraphPREFIX = "<#{BASE_URI}#{dataset_type}/context/>"
  fields = CBGP::Dataset.get_questionnaire_fields(questionnaire_type: dataset_type)

  query = <<~SPARQL
    #{PREFIXES}
    PREFIX dataset: #{datasetPREFIX}
    PREFIX datasetgraph: #{datasetgraphPREFIX}
    SELECT DISTINCT ?datasetgraph
    WHERE {
      GRAPH ?datasetgraph {
  SPARQL

  conditions = []
  search_params.each do |questionclass, value|
    field = fields.find { |f| f[:fieldid] == questionclass }
    next unless field

    if value.is_a?(Hash) # Date range – unchanged
      start_date = value['start']&.strip
      end_date = value['end']&.strip
      next if start_date.to_s.empty? && end_date.to_s.empty?

      filter = ''
      if !start_date.to_s.empty? && !end_date.to_s.empty?
        filter = "FILTER (?datevalue >= \"#{start_date}\"^^xsd:date && ?datevalue <= \"#{end_date}\"^^xsd:date)"
      elsif !start_date.to_s.empty?
        filter = "FILTER (?datevalue >= \"#{start_date}\"^^xsd:date)"
      elsif !end_date.to_s.empty?
        filter = "FILTER (?datevalue <= \"#{end_date}\"^^xsd:date)"
      end

      conditions << <<-CONDITION
        ?dataset sio:SIO_000008 ?attribute .
        ?attribute sio:SIO_000300 ?datevalue .
        ?attribute rdf:type cbgp:#{questionclass} .
        #{filter}
      CONDITION
    else # Text search – UPDATED: use unaccent in pattern building
      value_str = value.to_s.strip
      next if value_str.empty?

      if ACCENT_SENSITIVE_LABELS.include?(field[:label].downcase)
        # Accent-insensitive: build pattern from unaccented term
        pattern = accent_insensitive_pattern(value_str)
        next if pattern.empty?

        conditions << <<-CONDITION
          ?dataset sio:SIO_000008 ?attribute .
          ?attribute sio:SIO_000300 ?value .
          ?attribute rdf:type cbgp:#{questionclass} .
          FILTER regex(STR(?value), "#{pattern}", "i")
        CONDITION
      else
        # Standard – unchanged, but with downcase
        escaped_value = value_str.gsub('"', '\\"')
        conditions << <<-CONDITION
          ?dataset sio:SIO_000008 ?attribute .
          ?attribute sio:SIO_000300 ?value .
          ?attribute rdf:type cbgp:#{questionclass} .
          FILTER(CONTAINS(LCASE(STR(?value)), "#{escaped_value.downcase}"))
        CONDITION
      end
    end
  end

  return nil if conditions.empty?

  query += conditions.join("\n")
  query += <<~SPARQL
      }
    }
  SPARQL

  warn "Generated search query:\n#{query}\n\n\n"
  query
end

def execute_search(search_params:, dataset_type:)
  query = build_search_query(search_params: search_params, dataset_type: dataset_type)
  return [] unless query

  results = DATABASE.query(query)
  warn "Search results: #{results.map { |r| r.to_h }.inspect}"
  results.map { |result| result[:datasetgraph].to_s } # Return array of graph URIs
end

# def build_search_query(search_params:, dataset_type:)
#   # Early-exit guard clause: returns nil if the search_params do not contain any meaningful (non-empty) search criteria.
#   # This prevents running an expensive or meaningless search when the user submitted an empty/blanks-only form.
#   #
#   # It supports nested params (common in complex search forms, e.g., date ranges like { start: "", end: "" })
#   # by recursively checking inside hash values.
#   #
#   # Returns: the original search_params (implicitly, if it passes) or nil (if empty/blank).
#   return nil unless search_params.is_a?(Hash) && # Must be a hash...
#                     search_params.any? do |k, v| # ...and at least one key-value pair must satisfy:
#                       !v.nil? && # - Value is not nil
#                       ( # - AND the value is "non-blank" in one of two ways:
#                         (!v.is_a?(Hash) && !v.to_s.strip.empty?) || #   1. Simple scalar value (string, number, etc.):
#                         #      - Convert to string, strip whitespace, ensure not empty
#                         (v.is_a?(Hash) && v.values.any? do |val| #   2. Nested hash value (e.g., { gte: "2023", lte: "" }):
#                           !val.to_s.strip.empty? #      - At least one of its values, after to_s.strip, is non-empty
#                         end)
#                       )
#                     end

#   datasetPREFIX = "<#{BASE_URI}#{dataset_type}/dataset/>"
#   datasetgraphPREFIX = "<#{BASE_URI}#{dataset_type}/context/>"
#   fields = CBGP::Dataset.get_questionnaire_fields(questionnaire_type: dataset_type)

#   query = <<~SPARQL
#     #{PREFIXES}
#     PREFIX dataset: #{datasetPREFIX}
#     PREFIX datasetgraph: #{datasetgraphPREFIX}
#     SELECT DISTINCT ?datasetgraph
#     WHERE {
#       GRAPH ?datasetgraph {
#   SPARQL

#   conditions = []
#   search_params.each do |questionclass, value|
#     field = fields.find { |f| f[:fieldid] == questionclass }
#     next unless field

#     if value.is_a?(Hash) # Date range
#       start_date = value['start']&.strip
#       end_date = value['end']&.strip
#       next if start_date.to_s.empty? && end_date.to_s.empty?

#       filter = ''
#       if !start_date.to_s.empty? && !end_date.to_s.empty?
#         filter = "FILTER (?datevalue >= \"#{start_date}\"^^xsd:date && ?datevalue <= \"#{end_date}\"^^xsd:date)"
#       elsif !start_date.to_s.empty?
#         filter = "FILTER (?datevalue >= \"#{start_date}\"^^xsd:date)"
#       elsif !end_date.to_s.empty?
#         filter = "FILTER (?datevalue <= \"#{end_date}\"^^xsd:date)"
#       end

#       conditions << <<-CONDITION
#         ?dataset sio:SIO_000008 ?attribute .
#         ?attribute sio:SIO_000300 ?datevalue .
#         ?attribute rdf:type cbgp:#{questionclass} .
#         #{filter}
#       CONDITION
#     else
#       next if value.to_s.strip.empty?

#       escaped_value = value.to_s.gsub('"', '\"')
#       conditions << <<-CONDITION
#         ?dataset sio:SIO_000008 ?attribute .
#         ?attribute sio:SIO_000300 ?value .
#         ?attribute rdf:type cbgp:#{questionclass} .
#         FILTER(CONTAINS(LCASE(?value), LCASE("#{escaped_value}")))
#       CONDITION
#     end
#   end

#   return nil if conditions.empty?

#   query += conditions.join("\n")
#   query += <<~SPARQL
#       }
#     }
#   SPARQL

#   warn "Generated search query:\n#{query}\n\n\n"
#   query
# end

# Fetches metadata/details for a dataset graphs identified by their URIs.
# The details are pulled from a SPARQL endpoint using fields defined in a "questionnaire"
# for the given dataset_type (e.g., specific attributes like title, description, etc.).
# Returns an array of hashes, one hash per dataset URI, containing only the fields that
# actually have values.
def fetch_dataset_raw_data(graphuri:, database:)
  # Get the list of fields (metadata properties) that we care about for this dataset_type.
  # Each field is a hash with keys like :fieldid (the property name), :cardinality ('Multiple' or single), etc.
  fields = CBGP::Dataset.get_questionnaire_fields(questionnaire_type: database)

  # Build the SELECT clause: ?field1 ?field2 ?field3 ...
  select_clause = fields.map { |f| "?#{f[:fieldid]}" }.join(' ')

  # Build the WHERE clause: for each field, an OPTIONAL block that looks for
  #   ?dataset sio:SIO_000008 ?attributeXXX .
  #   ?attributeXXX sio:SIO_000300 ?XXX .          # the actual literal value
  #   ?attributeXXX rdf:type cbgp:XXX .            # typed as the specific property
  # This pattern is common in RDF data models that use reified attributes.
  where_clause = fields.map do |f|
    <<~SPARQL
      OPTIONAL {
        ?dataset sio:SIO_000008 ?attribute#{f[:fieldid]} .
        ?attribute#{f[:fieldid]} sio:SIO_000300 ?#{f[:fieldid]} .
        ?attribute#{f[:fieldid]} rdf:type cbgp:#{f[:fieldid]} .
      }
    SPARQL
  end.join("\n")

  # Full SPARQL query: prefixes + SELECT + WHERE { GRAPH <uri> { ... } }
  query = <<~SPARQL
    #{PREFIXES}
    SELECT #{select_clause}
    WHERE {
      GRAPH <#{graphuri}> {
        #{where_clause}
      }
    }
  SPARQL

  # Execute the query against the RDF/SPARQL database (DATABASE is a configured RDF::Repository or similar)
  result_set = DATABASE.query(query)

  # Start building a hash for this dataset's details, with the URI itself included
  details = { dataset: graphuri }

  # Now extract values from the query results for each field
  fields.each do |f|
    field_sym = f[:fieldid].to_sym # e.g., :title, :description

    if f[:cardinality] == 'Multiple'
      # For multi-valued fields: collect the value from EVERY solution (row),
      # convert to string (if present), remove nil, remove duplicates
      values = result_set.map { |r| r[field_sym]&.to_s }.compact.uniq
      # Only store the array if we actually found values
      details[field_sym] = values unless values.empty?
    else
      # For single-valued fields: take the value from the FIRST solution only
      # ---------------------------------------------------------
      details[field_sym] = result_set.first[field_sym]&.to_s # FIXED VERSION
    end
  end

  warn "Dataset details: #{details.inspect}"
  details
end
# this is the end of the world as we know it
