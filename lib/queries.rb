# frozen_string_literal: true

require 'linkeddata'
require 'sparql'
require 'sparql/client'
require 'securerandom'
# require 'unicode' # If not already available; Ruby stdlib has String#unicode_normalize, but ensure it's loaded if needed

host = GRAPHDB_HOST || 'localhost:7200'
GRAPHDB_USER || 'cbgp'
GRAPHDB_PASS || 'cbgp'
GRAPHDB_DBNAME || 'kbdatabase'

$ontology = RDF::Repository.load(CBGP_KB) # set in configuration.rb and/or in docker-compose
DATABASE = SPARQL::Client.new("http://#{GRAPHDB_USER}:#{GRAPHDB_PASS}@#{host}/repositories/#{GRAPHDB_DBNAME}")
DATABASE_UPDATE = SPARQL::Client.new("http://#{GRAPHDB_USER}:#{GRAPHDB_PASS}@#{host}/repositories/#{GRAPHDB_DBNAME}/statements")

# SCD Type 2 history repository — a separate GraphDB repository (not a
# namespaced graph in DATABASE) that holds snapshots of superseded/deleted
# records. See delete_dataset_query.
HISTORY_DATABASE = SPARQL::Client.new("http://#{HISTORY_USER}:#{HISTORY_PASS}@#{host}/repositories/#{GRAPHDB_HISTORY}")
HISTORY_DATABASE_UPDATE = SPARQL::Client.new("http://#{HISTORY_USER}:#{HISTORY_PASS}@#{host}/repositories/#{GRAPHDB_HISTORY}/statements")

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
        local:dbname ?dbname .  # this is just the string, like "project"
    }
GET_DBNAME
  warn "database name query\n\n#{qs}\n\n"
  qs = SPARQL.parse(qs)
  results = qs.execute($ontology)
  results.first[:dbname].to_s
end

def get_questionnaire_types_query(type: 'Core', language: current_language) # rubocop:disable Metrics/MethodLength
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

def get_questionnaire_sections_query(questionnaire_type:, language: current_language)
  return [] unless questionnaire_type

  warn "\n\nIn get_questionnaire_sections with #{questionnaire_type} and #{language}\n\n\n"

  # questionnaire_type = Add/Edit publications (#add-publication) has-fields Publication Questions (#new-publication-questions)

  qs = <<GET_QUESTIONNAIRE_SECTIONS
    #{PREFIXES}

    SELECT ?sec (str(?seclab) as ?label) WHERE {
      cbgp:#{questionnaire_type} local:has-fields ?sec . # "publication", "project", "member"
      ?sec rdfs:label ?seclab .
      FILTER (lang(?seclab) = "#{language}")
    }
GET_QUESTIONNAIRE_SECTIONS
  warn "QUERY IS #{qs} on ontology #{$ontology} #{$ontology.size}"
  qs = SPARQL.parse(qs)
  result = qs.execute($ontology)
  warn "questionnaire_sections_query result: #{result.inspect}"
  result
end

def get_section_questions_query(sectionid:, language: current_language)
  qs = <<GET_SECTION_QUESTIONS
    #{PREFIXES}

    SELECT ?q (str(?qlab) as ?label) ?widget ?class ?method ?cardinality ?answers ?primary ?sequence ?references ?references_via ?references_label (str(?qcomment) as ?comment) WHERE {
    ?q rdfs:subClassOf cbgp:#{sectionid} .
    ?q rdfs:label ?qlab .
    FILTER (lang(?qlab) = "#{language}")
    ?q local:widget-type ?widget .
    ?q local:widget-cardinality ?cardinality .
    ?q local:answer-block ?answers .
    ?q local:method ?method .
    ?q local:question-order ?sequence .
    OPTIONAL {?q local:object-class ?class }.
    OPTIONAL {?q local:is-primary-id ?primary }.
    OPTIONAL { ?q local:references ?references . }
    OPTIONAL { ?q local:references-via ?references_via . }
    OPTIONAL { ?q local:references-label ?references_label . }
    OPTIONAL { ?q rdfs:comment ?qcomment . FILTER (lang(?qcomment) = "#{language}") }
  } ORDER BY ?sequence

GET_SECTION_QUESTIONS
  qs = SPARQL.parse(qs)
  qs.execute($ontology)
end

# Fetches a form's pre-populated defaults: the local:has-defaults branch lets
# a form assign a default answer to one of its fields *without* that default
# living on the shared question class itself — necessary because the same
# question class can be reused across multiple forms (e.g. a field shared by
# both Research and Personnel projects), each of which may want a different
# default, or none at all.
#
#   cbgp:personnel_project local:has-defaults cbgp:some_default_node .
#   cbgp:some_default_node local:default-for-field cbgp:project_x ;
#                           local:default-value    "some value" .
#
# @param form_class [String] the specific form class fragment, e.g.
#   "personnel_project" - NOT the shared dbname ("project")
# @return [SPARQL::Client::Solutions] rows with ?field (full URI) and ?value
def get_form_defaults_query(form_class:)
  qs = <<~GET_FORM_DEFAULTS
    #{PREFIXES}
    SELECT ?field ?value WHERE {
      cbgp:#{form_class} local:has-defaults ?d .
      ?d local:default-for-field ?field ;
         local:default-value ?value .
    }
  GET_FORM_DEFAULTS
  qs = SPARQL.parse(qs)
  qs.execute($ontology)
end

# Fetches which of a FORM's fields are mandatory, per local:requires-field
# (see the AnnotationProperty declaration in the .owl file for the full
# rationale — short version: unlike local:has-defaults, "required" carries
# no extra data beyond "yes, this field", so it's a single direct property
# straight from the form to the question class, not a two-piece reified
# node like a default is).
#
# This is a SIBLING query to get_form_defaults_query above, not a variant of
# it — deliberately kept as its own small, single-purpose SPARQL string
# (rather than, say, cramming an extra OPTIONAL onto some other query)
# because it answers a genuinely different question: "does this exist for
# this form?" rather than "what value does this have for this form?".
#
#   cbgp:personnel_project local:requires-field cbgp:project_annual_income .
#
# @param form_class [String] the specific form class fragment, e.g.
#   "personnel_project" — the same "must be the real form, not the shared
#   dbname" caveat as get_form_defaults_query applies here too: this has to
#   be called with the actual form (e.g. "personnel_project"), never with
#   the dbname ("project"), or every form sharing that dbname would appear
#   to require the same fields.
# @return [SPARQL::Client::Solutions] rows with a single ?field (full URI)
#   binding per required field — there is no "value" column here, only
#   presence/absence of a row for a given field
def get_form_required_fields_query(form_class:)
  qs = <<~GET_FORM_REQUIRED_FIELDS
    #{PREFIXES}
    SELECT ?field WHERE {
      cbgp:#{form_class} local:requires-field ?field .
    }
  GET_FORM_REQUIRED_FIELDS
  qs = SPARQL.parse(qs)
  qs.execute($ontology)
end

# Fetches a form's calculated-field formulas: the local:has-formulas branch,
# a THIRD sibling of has-defaults/requires-field above (see the
# local:has-formulas AnnotationProperty comment in the .owl file for the
# full rationale). Shaped exactly like get_form_defaults_query — a formula
# is TWO pieces of data per (form, field) (which field, AND the formula
# text), so it needs the same reified intermediate-node shape as a default
# does, not the direct-property shape "required" uses.
#
#   cbgp:project local:has-formulas cbgp:some_formula_node .
#   cbgp:some_formula_node local:formula-for-field  cbgp:project_cbgp_overheads ;
#                           local:formula-expression "project_total_funding * 0.13" .
#
# @param form_class [String] the specific form class fragment, e.g.
#   "project" - same caveat as its siblings: must be the real form class,
#   never the shared dbname.
# @return [SPARQL::Client::Solutions] rows with ?field (full URI) and
#   ?formula (the Dentaku expression string) per calculated field this form
#   declares
def get_form_formulas_query(form_class:)
  qs = <<~GET_FORM_FORMULAS
    #{PREFIXES}
    SELECT ?field ?formula WHERE {
      cbgp:#{form_class} local:has-formulas ?f .
      ?f local:formula-for-field  ?field ;
         local:formula-expression ?formula .
    }
  GET_FORM_FORMULAS
  qs = SPARQL.parse(qs)
  qs.execute($ontology)
end

def get_answer_block_query(ablockid:, language: current_language)
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

def get_hierarchical_answer_block_query(ablockid:, language: current_language)
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

def get_label_for_questionnaire_type(id:, language: current_language)
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

def get_label_for_id(id:, language: current_language)
  return nil if id.nil? || id.empty?

  # Strip the document fragment from the URI if it includes a '#'
  id = id.to_s.split('#').last if id.to_s.include?('#')

  query = <<~LABEL_QUERY
    #{PREFIXES}
    SELECT ?label WHERE {
    cbgp:#{id} rdfs:label ?label .
    FILTER (lang(?label) = '#{language}')
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

def field_query(fieldid:, language: current_language)
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

##############################################################################
# Dataset persistence — SPARQL queries for reading, writing, and deleting
# records stored as named graphs.
#
# Each record lives in its own named graph whose URI follows the pattern:
#   #{BASE_URI}<form_type>/context/<primary_id>
#
# Inside the graph, fields are encoded using the SIO reified-attribute pattern:
#   <dataset_node> sio:SIO_000008 <attribute_node> .
#   <attribute_node> rdf:type cbgp:<questionclass> ;
#                    sio:SIO_000300 "<literal_value>" .
#
# Provenance triples (dcterms:created / dcterms:modified) are written into the
# DEFAULT graph (outside the named graph) so they survive graph-level queries.
# Consequently, delete_dataset_query must remove them explicitly before dropping
# the named graph.
##############################################################################

# Finds the named graph URI that contains a record with the given primary_id.
# Searches across all graphs for a node whose sio:SIO_000115 (identifier) has
# the given string value.  Returns a SPARQL result set; the caller reads +[:g]+.
#
# @note Prone to collisions if two records share the same primary_id string
#   across different form types.  Scoping by graph prefix would eliminate this.
#
# @param primary_id [String] the record's primary identifier value
# @return [SPARQL::Client::Solutions] result rows with +?g+ bound to the graph URI
def retrieve_dataset_graph_query(primary_id:)
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
  DATABASE.query(retds)
end

# Returns the primary_id string stored inside a known named graph.
# Useful when you have a graph URI (e.g. from a search result) and need to
# recover the human-facing identifier without loading the full record.
#
# @param graph [String] the full named graph URI
# @return [String, nil] the primary_id value, or +nil+ if the graph has none
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
  results = DATABASE.query(retds)
  return results.first[:id].to_s if results

  nil
end

# Escapes a value for safe embedding in a SPARQL string literal.
#
# Must use the block form of gsub, not a string replacement: gsub
# re-interprets backslash sequences (\\, \1, \&, …) in a *string*
# replacement, so `gsub('\\', '\\\\')` — intended to double every backslash
# — is actually a no-op (the "doubled" replacement collapses back down to a
# single literal backslash on the way out). A block's return value is
# inserted literally, with no second interpretation pass, so this is safe.
#
# @param value [Object]
# @return [String]
def escape_for_literal(value)
  value.to_s.gsub(/["\\]/) { |c| "\\#{c}" }
end

# Removes a named graph from the CURRENT-state repository (DATABASE), first
# snapshotting its prior state into the separate HISTORY repository
# (HISTORY_DATABASE/HISTORY_DATABASE_UPDATE) — this is the SCD Type 2
# recording mechanism. Called for both true deletes (reason: 'deleted', the
# default — single/multi-select delete, utilities/purge_dataset.rb) and, from
# write_dataset_to_db_query, edits (reason: 'superseded').
#
# Steps:
#   1. Read the live graph's own dcterms:created/dcterms:modified (default
#      graph, subject = graph URI) before touching anything. dcterms:modified
#      becomes the snapshot's prov:generatedAtTime (when *this* version
#      became current); dcterms:created is returned so the caller can
#      preserve it into the new write instead of losing it (a pre-existing
#      bug: this same DELETE wipes it and nothing rewrites it after an edit).
#   2. CONSTRUCT the old graph's triples out of DATABASE (read-only) and
#      INSERT them verbatim into a freshly-named graph in HISTORY_DATABASE,
#      then annotate that snapshot graph at the graph level (subject = the
#      snapshot's own URI, not a resource inside it — deliberately
#      nanopub/PROV-style, not mixed into the assertion data) with
#      prov:generatedAtTime/prov:invalidatedAtTime/local:history-reason/
#      local:history-detail, all living in HISTORY_DATABASE's default graph.
#      Two independent repositories are used — no SPARQL federation, no
#      INSERT-WHERE across connections.
#   3. Only then remove the live graph (and its default-graph provenance)
#      from DATABASE — unchanged from the original delete logic.
#
# @param oldid [String] the full named graph URI to delete (in DATABASE)
# @param reason ['deleted', 'superseded'] why this version is ending
# @param detail [String, nil] heuristic human-readable summary of what
#   changed (see CBGP::Dataset... summarize_field_changes in lib/core.rb);
#   defaults to "Record deleted" when reason is 'deleted' and none is given
# @return [Hash] +{ created:, history_graph: }+ — +created+ is the prior
#   dcterms:created value (or nil for a brand-new record), for the caller to
#   preserve; +history_graph+ is the new snapshot's graph URI
def delete_dataset_query(oldid:, reason: 'deleted', detail: nil)
  detail ||= 'Record deleted' if reason == 'deleted'
  form_type, primary_id = oldid.match(%r{\A#{Regexp.escape(BASE_URI)}(.+)/context/(.+)\z})&.captures

  prov_results = DATABASE.query(<<~PROV)
    #{PREFIXES}
    SELECT ?created ?modified WHERE {
      OPTIONAL { <#{oldid}> dcterms:created  ?created }
      OPTIONAL { <#{oldid}> dcterms:modified ?modified }
    }
  PROV
  created = prov_results.first&.bound?(:created) ? prov_results.first[:created].to_s : nil
  generated_at = prov_results.first&.bound?(:modified) ? prov_results.first[:modified].to_s : Time.now.utc.iso8601

  history_graph = "#{BASE_URI}#{form_type}/history/#{primary_id}/#{SecureRandom.uuid}"
  now = Time.now.utc.iso8601

  old_triples = DATABASE.query(<<~CONSTRUCT)
    #{PREFIXES}
    CONSTRUCT { ?s ?p ?o } WHERE { GRAPH <#{oldid}> { ?s ?p ?o } }
  CONSTRUCT
  HISTORY_DATABASE_UPDATE.insert_data(old_triples, graph: history_graph)

  HISTORY_DATABASE_UPDATE.update(<<~META)
    #{PREFIXES}
    PREFIX prov: <http://www.w3.org/ns/prov#>
    INSERT DATA {
      <#{history_graph}> prov:generatedAtTime    "#{generated_at}"^^xsd:dateTime ;
                          prov:invalidatedAtTime  "#{now}"^^xsd:dateTime ;
                          local:history-reason    "#{escape_for_literal(reason)}" ;
                          local:history-detail    "#{escape_for_literal(detail)}" .
    }
  META

  DATABASE_UPDATE.update(<<~DELETE_DATASET)
    #{PREFIXES}
    DELETE WHERE { <#{oldid}> ?p ?o } ;
    DROP GRAPH <#{oldid}>
  DELETE_DATASET

  { created: created, history_graph: history_graph }
end

# Executes the SPARQL UPDATE that persists a dataset to the triple store.
# When +oldid+ is supplied the old graph is deleted first, so this method
# serves both INSERT (new record) and REPLACE (edit) semantics.
#
# @param dataset [CBGP::Dataset] the populated dataset object to write
# @param oldid [String, nil] primary_id of the graph to delete before writing;
#   pass the same value as +dataset.primary_id+ to replace an existing record
#   while preserving its URI
# @return [Object] raw response from the SPARQL update endpoint
def write_dataset_to_db(dataset:, oldid: nil, form: nil)
  writequery = write_dataset_to_db_query(dataset: dataset, oldid: oldid, form: form)
  warn "WRITE DATASET QUERY\n#{writequery}\n\n\n"
  resp = DATABASE_UPDATE.update(writequery)
  warn "write dataset response #{resp.inspect}"
  resp
end

# Builds the SPARQL UPDATE string that inserts a dataset's triples.
#
# If +oldid+ is given, the old graph is first snapshotted into the SCD Type 2
# history repository and dropped (see +delete_dataset_query+, reason:
# 'superseded'), then an INSERT DATA block is constructed containing:
#   - Core typing triples (rdf:type sio:SIO_000089, cbgp:<form_type>)
#   - An sio:SIO_000115 identifier node carrying the primary_id string
#   - One attribute node per field value, using the SIO reified-attribute pattern
#   - Provenance triples in the DEFAULT graph:
#       * dcterms:modified — always written (timestamp of this write)
#       * dcterms:created  — always written; preserved from the prior version
#         on an edit (via delete_dataset_query's return value) rather than
#         reset, so creation date survives edits instead of being lost
#       * dcterms:type — always written; the FORM CLASS that produced this
#         record (e.g. cbgp:personnel_project), not the shared dbname. This
#         is what replaced project_category (a real, ontology-declared
#         field with its own default-per-form value) with something
#         structural: every record on every form gets this automatically,
#         with zero ontology configuration, because it's written directly
#         from the +form:+ parameter that's already threaded through the
#         whole save path (see CBGP::Dataset.load_from_params_and_write) -
#         nothing for an ontology editor to remember to declare, and no
#         "forgot to add has-defaults for the new form" gap possible. The
#         object is the form class URI itself, not a string, so its
#         display label resolves for free via get_label_for_id/
#         cached_label_for_id (lib/core.rb) - already generic over any
#         cbgp:<id> rdfs:label, and every form class already has one, so
#         nothing new was needed for this to work.
#
# Multiple-cardinality fields produce one numbered attribute node per value:
#   <dataset>/<questionclass>_1, <dataset>/<questionclass>_2, …
#
# @param dataset [CBGP::Dataset] the dataset to serialise
# @param oldid [String, nil] if present, the old graph is snapshotted+dropped
#   before insert
# @param form [String, nil] the specific FORM class that produced this
#   write (e.g. "personnel_project") - NOT the shared dbname. Defaults to
#   +dataset.form_type+ (the dbname) when not given, which is only correct
#   for a dbname with exactly one form - callers that know the true form
#   (i.e. +load_from_params_and_write+) must pass it explicitly.
# @return [String] the complete SPARQL UPDATE query string
def write_dataset_to_db_query(dataset:, oldid: nil, form: nil)
  database = dataset.form_type
  form = database if form.to_s.strip.empty?
  primary_id = dataset.primary_id
  warn "WRITE DATASET primary_id is #{primary_id}\n\n"

  captured = nil
  if oldid
    old_graph_uri = "#{BASE_URI}#{database}/context/#{oldid}"
    old_values = fetch_datasets_raw_data(graph_uris: [old_graph_uri], database: database).first || {}
    detail = summarize_field_changes(fields: dataset.fields, old_values: old_values, new_dataset: dataset)
    captured = delete_dataset_query(oldid: old_graph_uri, reason: 'superseded', detail: detail)
  end

  datasetPREFIX         = "<#{BASE_URI}#{database}/dataset/>"
  datasetgraphPREFIX    = "<#{BASE_URI}#{database}/context/>"
  datasetFragmentPREFIX = "<#{BASE_URI}#{database}/dataset/#{primary_id}#>"
  graph_uri             = "#{datasetgraphPREFIX}#{primary_id}" # Full named graph URI (used for provenance)

  # Current UTC timestamp in ISO8601 format (xsd:dateTime compatible literal)
  timestamp = Time.now.utc.iso8601

  triples = []
  triples << "dataset:#{primary_id} rdf:type sio:SIO_000089 ;"
  triples << "   rdf:type cbgp:#{database} ;"
  triples << '   sio:SIO_000671 datasetfrag:primary_id .'
  triples << "   datasetfrag:primary_id sio:SIO_000300 \"#{primary_id}\" ;"
  triples << '           rdf:type sio:SIO_000115 . # sio: identifier'

  dataset.fields.each do |field|
    next unless dataset.respond_to?(field[:method])

    value = dataset.public_send(field[:method])
    next if value.nil? || (value.is_a?(Array) && value.empty?)

    questionclass = field[:questionclass]

    if field[:cardinality] == 'Multiple' && value.is_a?(Array)
      value.each_with_index do |val, index|
        next if val.to_s.strip.empty?

        this_attribute = "#{datasetPREFIX.gsub(/[<>]/, '')}#{primary_id}/#{questionclass}_#{index + 1}"
        triples << "dataset:#{primary_id} sio:SIO_000008 <#{this_attribute}> ."
        triples << "<#{this_attribute}> rdf:type cbgp:#{questionclass} ."
        triples << "<#{this_attribute}> sio:SIO_000300 \"#{escape_for_literal(val)}\" ."
      end
    else
      this_attribute = "#{datasetPREFIX.gsub(/[<>]/, '')}#{primary_id}/#{questionclass}"
      triples << "dataset:#{primary_id} sio:SIO_000008 <#{this_attribute}> ."
      triples << "<#{this_attribute}> rdf:type cbgp:#{questionclass} ."
      triples << "<#{this_attribute}> sio:SIO_000300 \"#{escape_for_literal(value)}\" ."
    end
  end

  body = triples.join("\n")

  # Provenance triples are intentionally written OUTSIDE the GRAPH {} block so
  # they land in the default graph.  This keeps them queryable without knowing
  # the graph URI and means delete_dataset_query must clean them up explicitly.
  # dcterms:created is preserved from the prior version on an edit (captured
  # by delete_dataset_query above) rather than reset, so it survives edits.
  created_value = captured&.dig(:created) || timestamp
  prov = "datasetgraph:#{primary_id} dcterms:modified \"#{timestamp}\"^^xsd:dateTime ."
  prov += "datasetgraph:#{primary_id} dcterms:created \"#{created_value}\"^^xsd:dateTime ."
  prov += "datasetgraph:#{primary_id} dcterms:type cbgp:#{form} ."

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
  base_term.gsub(/./) { |char| mapping[char] || sparql_regex_escape(char) }
end

# Escapes a single character for safe use inside a SPARQL FILTER regex(...)
# string-literal argument.
#
# NOTE: this is deliberately NOT Ruby's Regexp.escape. SPARQL's regex()
# function uses XPath F&O regex syntax, and the pattern is embedded inside a
# SPARQL string literal. Ruby's Regexp.escape escapes characters (like a
# plain space, to survive Ruby's own /x extended-mode regexes) that are
# meaningless to escape here and that SPARQL's string-literal grammar
# actually rejects — e.g. Regexp.escape(' ') => '\ ', and "\ " is not a
# legal SPARQL string escape, which previously caused a lexical error on any
# multi-word search term (e.g. "My Innovative Project").
def sparql_regex_escape(char)
  case char
  when '"', '\\' then "\\#{char}" # must not break out of the SPARQL string literal
  when '.', '*', '+', '?', '(', ')', '[', ']', '{', '}', '|', '^', '$' then "\\#{char}" # XPath regex metacharacters
  else char
  end
end

def build_search_query(search_params:, dataset_type:)
  return nil unless search_params.is_a?(Hash) &&
                    search_params.any? do |k, v|
                      !v.nil? &&
                      (
                        (!v.is_a?(Hash) && !v.to_s.strip.empty?) ||
                        (v.is_a?(Hash) && v.values.any? { |val| !val.to_s.strip.empty? })
                      )
                    end

  # OPTIMIZATION: Use the exact cached fields (with :questionclass, :label, etc.)
  fields = CBGP::Dataset.fields_for(dataset_type)
  warn "\n\n\nFIELDS #{fields}\n\n\n"
  datasetPREFIX = "<#{BASE_URI}#{dataset_type}/dataset/>"
  datasetgraphPREFIX = "<#{BASE_URI}#{dataset_type}/context/>"

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
    field = fields.find { |f| f[:questionclass] == questionclass }

    if field.nil?
      warn "WARNING: No field found for questionclass '#{questionclass}' in #{dataset_type} – skipping this search term"
      next
    end

    if value.is_a?(Hash) # Date range
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
    else # Text / dropdown value
      value_str = value.to_s.strip
      next if value_str.empty?

      if field[:class] == 'currency'
        # Search input is typed in the current UI language's number
        # convention (e.g. "15.000,50" in Spanish); normalize it to the
        # canonical decimal form the value is actually stored in before
        # matching, same as on save. Skip silently on unparseable input,
        # like every other search field does on a blank/invalid term.
        parsed = parse_currency_input(value_str)
        next unless parsed

        conditions << <<-CONDITION
          ?dataset sio:SIO_000008 ?attribute .
          ?attribute sio:SIO_000300 ?value .
          ?attribute rdf:type cbgp:#{questionclass} .
          FILTER(CONTAINS(STR(?value), "#{parsed}"))
        CONDITION
      else
        # Accent-insensitive by default for every free-text/dropdown field.
        # Previously this was opt-in per field via an ACCENT_SENSITIVE_LABELS
        # allowlist keyed on the ontology's human-readable (and
        # language-specific, and rewording-prone) field label, which is how
        # fields silently fell out of coverage — e.g. "member_name" was never
        # added, and label rewordings ("affiliation" -> "Affiliations",
        # "partner institutions" -> "Partner institutions (acronym and
        # country)") broke the exact-string match for fields that WERE
        # supposedly covered. Matching is now unconditional, so there is no
        # list to fall out of sync.
        pattern = accent_insensitive_pattern(value_str)
        next if pattern.empty?

        conditions << <<-CONDITION
          ?dataset sio:SIO_000008 ?attribute .
          ?attribute sio:SIO_000300 ?value .
          ?attribute rdf:type cbgp:#{questionclass} .
          FILTER regex(STR(?value), "#{pattern}", "i")
        CONDITION
      end
    end
  end

  if conditions.empty?
    warn 'WARNING: No valid search conditions generated – returning empty results'
    return nil
  end

  query += conditions.join("\n")
  query += <<~SPARQL
      }
    }
  SPARQL

  warn "Generated search query:\n#{query}\n\n\n"
  query
end

def execute_search(dataset_type:, search_params: {}, broad: false)
  if broad || search_params.empty? # Treat empty params as broad request
    warn "[BROAD SEARCH] Fetching all graphs for #{dataset_type}"
    return search_for_all_graphs(dataset_type: dataset_type)
  end

  query = build_search_query(search_params: search_params, dataset_type: dataset_type)
  warn "Generated search query:\n#{query || 'NIL QUERY'}"
  return [] unless query

  results = DATABASE.query(query)
  warn "Search results count: #{results.count}"
  results.map { |r| r[:datasetgraph].to_s }
end

def search_for_all_graphs(dataset_type:)
  query = search_all_graphs_query(dataset_type: dataset_type)
  warn "\n\n\nBROAD SEARCH QUERY IS #{query}\n\n\n"

  return [] unless query

  results = DATABASE.query(query)
  warn "Search results: #{results.map { |r| r.to_h }.inspect}"
  results.map { |result| result[:datasetgraph].to_s } # Return array of graph URIs
end

def search_all_graphs_query(dataset_type:)
  # [Unchanged early-exit guard]

  datasetPREFIX = "<#{BASE_URI}#{dataset_type}/dataset/>"
  datasetgraphPREFIX = "<#{BASE_URI}#{dataset_type}/context/>"

  query = <<~SPARQL
    #{PREFIXES}
    SELECT DISTINCT ?datasetgraph
    WHERE {
      GRAPH ?datasetgraph {
      ?s a cbgp:#{dataset_type}
      }
    }
  SPARQL

  warn "Generated search query:\n#{query}\n\n\n"
  query
end

# Fetches metadata/details for a dataset graphs identified by their URIs.
# The details are pulled from a SPARQL endpoint using fields defined in a "questionnaire"
# for the given dataset_type (e.g., specific attributes like title, description, etc.).
# Returns an array of hashes, one hash per dataset URI, containing only the fields that
# actually have values.
def fetch_datasets_raw_data(graph_uris:, database:)
  graph_uris = [graph_uris] unless graph_uris.is_a? Array
  return [] if graph_uris.empty?

  # OPTIMIZATION: Use cached exact fields
  fields = CBGP::Dataset.fields_for(database)

  # Build SELECT: ?graph + all ?questionclass vars
  select_clause = '?graph ' + fields.map { |f| "?#{f[:questionclass]}" }.join(' ')

  # Build VALUES clause for all graphs
  values_clause = "VALUES ?graph { #{graph_uris.map { |g| "<#{g}>" }.join(' ')} }"

  # Build WHERE: OPTIONAL blocks per field
  where_clause = fields.map do |f|
    <<~SPARQL
      OPTIONAL {
        GRAPH ?graph {
          ?dataset sio:SIO_000008 ?attribute#{f[:questionclass]} .
          ?attribute#{f[:questionclass]} sio:SIO_000300 ?#{f[:questionclass]} .
          ?attribute#{f[:questionclass]} rdf:type cbgp:#{f[:questionclass]} .
        }
      }
    SPARQL
  end.join("\n")

  # Full batched query
  query = <<~SPARQL
    #{PREFIXES}
    SELECT #{select_clause}
    WHERE {
      #{values_clause}
      #{where_clause}
    }
  SPARQL

  warn "BATCHED FETCH QUERY:\n#{query}\n\n"

  result_set = DATABASE.query(query)

  # Group results by graph (handles multi-row per graph for multi-valued fields)
  grouped = result_set.group_by { |r| r[:graph].to_s }

  grouped.map do |graph_uri, rows|
    details = { dataset: graph_uri }

    fields.each do |f|
      field_sym = f[:questionclass].to_sym

      if f[:cardinality] == 'Multiple'
        values = rows.flat_map { |r| r[field_sym]&.to_s }.compact.uniq
        details[field_sym] = values unless values.empty?
      elsif rows.first&.bound?(field_sym)
        details[field_sym] = rows.first[field_sym]&.to_s
      end
    end

    warn "BATCHED DETAILS FOR #{graph_uri}: #{details.inspect}"
    details
  end
end

def batch_retrieve_dataset_ids(graph_uris:)
  return {} if graph_uris.empty?

  # Build VALUES for all graphs
  values_clause = "VALUES ?graph { #{graph_uris.map { |g| "<#{g}>" }.join(' ')} }"

  query = <<~SPARQL
    #{PREFIXES}
    SELECT ?graph ?id
    WHERE {
      #{values_clause}
      GRAPH ?graph {
        ?dataset sio:SIO_000671 ?idnode .
        ?idnode sio:SIO_000300 ?id ;
          rdf:type sio:SIO_000115 .  # identifier
      }
    }
  SPARQL

  warn "BATCHED PRIMARY_ID QUERY:\n#{query}\n\n"

  results = DATABASE.query(query)

  # Build hash: graph_uri => primary_id (string)
  results.each_with_object({}) do |row, hash|
    graph = row[:graph].to_s
    id = row[:id]&.to_s
    hash[graph] = id if id
  end
end
