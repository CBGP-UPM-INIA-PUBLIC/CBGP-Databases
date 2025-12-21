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
"

def get_questionnaire_types_query(language: $language)
  # questionnaire_type = Add/Edit publications (#add-publication) has-fields Publication Questions (#new-publication-questions)

  qs = <<GET_QUESTIONNAIRE_TYPES
    #{PREFIXES}

    SELECT ?questionnaire_type ?questionnaire_label WHERE {
      ?questionnaire_type rdfs:subClassOf cbgp:forms .
      ?questionnaire_type rdfs:label ?questionnaire_label .
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

###################### Publications ##################
###################### Publications ##################
###################### Publications ##################
###################### Publications ##################
###################### Publications ##################
###################### Publications ##################

# core = retrieve_publication_core_query(doi: doi, graph: graph)
# auths = retrieve_publication_auths_query(doi: doi, graph: graph)
# affils = retrieve_publication_affils_query(doi: doi, graph: graph)

# def retrieve_publication_core_query(doi:, graph:)
#   publication = <<~READ_PUB
#           #{PREFIXES}

#     SELECT   ?doi ?scopusq ?scopusd1 ?oa ?sochoa ?pubtype ?title ?date ?journal ?volume
#     WHERE{ GRAPH <#{graph}> {
#                 ?publicationn rdf:type sio:SIO_000087 ;  # n equates to "node", without n is "value"
#                     sio:SIO_000671 ?idn ;
#                     cbgp:has_scopus_q ?scopusqn ;
#                     cbgp:has_scopus_d ?scopusd1n ;
#                     cbgp:is_open_access ?oan ;
#                     cbgp:has_so_acknowledgement ?sochoan ;
#                     cbgp:cbgp_corresponding ?cbgp_correspondingn ;
#                     cbgp:is_publication_type ?pubtypen ;
#                     cbgp:has_title ?titlen ;
#                     cbgp:has_volume ?volumen ;
#                     cbgp:has_publication_year ?yearn ;
#                     cbgp:is_published_in ?journaln .

#                 ?idn  sio:SIO_000300 ?doi ;
#                               rdf:type sio:SIO_000115 ;
#                               rdf:type edam:data_1188 .

#                 ?scopusqn  sio:SIO_000300 ?scopusq ;
#                               rdf:type cbgp:scopusq .

#                 ?scopusd1n  sio:SIO_000300 ?scopusd1 ;
#                               rdf:type cbgp:scopusd1 .

#                 ?oan  sio:SIO_000300 ?oa ;
#                               rdf:type cbgp:oa .

#                 ?sochoan  sio:SIO_000300 ?sochoa ;
#                               rdf:type cbgp:sochoa .

#                 ?cbgp_correspondingn  sio:SIO_000300 ?cbgp_corresponding ;
#                               rdf:type cbgp:cbgp_corresponding .

#                 ?pubtypen  sio:SIO_000300 ?pubtype ;
#                               rdf:type cbgp:pubtype .

#                 ?titlen  sio:SIO_000300 ?title ;
#                               rdf:type cbgp:title .

#                 ?daten  sio:SIO_000300 ?date ;
#                               rdf:type sio:SIO_001314 .

#                 ?journaln  sio:SIO_000300 ?journal ;
#                               rdf:type cbgp:journal ;
#                               rdf:type obo:GSSO_004587 .

#                 ?volumen  sio:SIO_000300 ?volume ;
#                               rdf:type cbgp:volume .

#                     }}

#   READ_PUB
#   PUBLICATIONS.query(publication)
# end

# def retrieve_publication_affils_query(doi:, graph:)
#   publication = <<READ_AFFILS
#     #{PREFIXES}
#     SELECT ?affiliation
#     WHERE { GRAPH <#{graph}> {
#           ?publication cbgp:has_affiliation ?affiliationn .

#           ?affiliationn  sio:SIO_000300 ?affiliation ;
#                         rdf:type sio:SIO_000012 .  # organization
#     }}
# READ_AFFILS
#   DATABASE.query(publication)
# end

# def retrieve_publication_auths_query(doi:, graph:)
#   publication = <<READ_AUTHORS
#   #{PREFIXES}
#   SELECT ?name ?orcid ?rank
#   WHERE { GRAPH <#{graph}> {
#         ?publication cbgp:has_author ?authorn .

#         ?authorn  sio:SIO_000300 ?name ;
#                       sio:SIO_000671 ?authidn ;
#                       rdf:type ncit:NCIT_C42781 .  # Author
#         ?authidn sio:SIO_000300 ?orcid ;
#                       rdf:type edam:data_4022 ; # ORCiD Identifier
#                       cbgp:author_rank ?rank.

#   }}
# READ_AUTHORS
#   warn "publication is: \n\n #{publication}\n\n"
#   DATABASE.query(publication)
# end

# def retrieve_pub_graph_query(doi:)
#   retpub = <<SELECT_PUB
#         #{PREFIXES}
#   select ?g where {
#   graph ?g {
#       ?pub sio:SIO_000671 ?id .

#       ?id  sio:SIO_000300 "#{doi}" ;
#         rdf:type sio:SIO_000115 ; # identifier
#         rdf:type edam:data_1188 . # doi
#   }}

# SELECT_PUB
#   # pubexists = SPARQL.parse(retpub)  # validate query or die
#   DATABASE.query(retpub)
# end

# def delete_pub_query(pubid:)
#   delete = <<DELETE_PUB
#   DROP GRAPH <#{pubid}>

# DELETE_PUB
#   DATABASE_UPDATE.update(delete)
# end

# def write_pub_to_db_query(pub:, oldid: nil)
#   delete_pub_query(pubid: oldid) if oldid
#   publication = <<~WRITE_PUB
#           #{PREFIXES}

#     PREFIX pub:  <http://admin.cbgp.upm.es/graphs/publications/#{pub.uniqid}#>
#     PREFIX pubgraph:  <hhttp://admin.cbgp.upm.es/graphs/publications/#{pub.uniqid}#>

#     INSERT DATA { GRAPH pub:container {
#                 pubgraph:publication rdf:type sio:SIO_000087 ;  # publication
#                     sio:SIO_000671 pubgraph:id ;
#                     cbgp:has_scopus_q pubgraph:scopusq ;
#                     cbgp:has_scopus_d pubgraph:scopusd1 ;
#                     cbgp:is_open_access pubgraph:oa ;
#                     cbgp:cbgp_corresponding pubgraph:cbgp_corresponding ;
#                     cbgp:has_so_acknowledgement pubgraph:sochoa ;
#                     cbgp:is_publication_type pubgraph:pubtype ;
#                     cbgp:has_title pubgraph:title ;
#                     cbgp:has_journal pubgraph:journal ;
#                     cbgp:has_volume pubgraph:volume ;
#                     cbgp:has_publication_year pubgraph:year ;
#                     cbgp:is_published_in pubgraph:journal .
#                 pubgraph:id  sio:SIO_000300 "#{pub.doi}" ;
#                               rdf:type sio:SIO_000115 ; # identifier
#                               rdf:type edam:data_1188 . # doi

#                 pubgraph:scopusq  sio:SIO_000300 "#{pub.scopusq}" ;
#                               rdf:type cbgp:scopusq .

#                 pubgraph:scopusd1  sio:SIO_000300 "#{pub.scopusd1}" ;
#                               rdf:type cbgp:scopusd1 .

#                 pubgraph:oa  sio:SIO_000300 "#{pub.oa}" ;
#                               rdf:type cbgp:oa .

#                 pubgraph:sochoa  sio:SIO_000300 "#{pub.sochoa}" ;
#                               rdf:type cbgp:sochoa .

#                 pubgraph:cbgp_corresponding  sio:SIO_000300 "#{pub.cbgp_corresponding}" ;
#                               rdf:type cbgp:cbgp_corresponding .

#                 pubgraph:pubtype  sio:SIO_000300 "#{pub.pubtype}" ;
#                               rdf:type cbgp:pubtype .

#                 pubgraph:title  sio:SIO_000300 "#{pub.title}" ;
#                               rdf:type cbgp:title .

#                 pubgraph:date  sio:SIO_000300 "#{pub.date}" ;
#                               rdf:type sio:SIO_001314 .  # date of issue

#                 pubgraph:journal  sio:SIO_000300 "#{pub.journal}" ;
#                               rdf:type cbgp:journal ;
#                               rdf:type obo:GSSO_004587 .

#                 pubgraph:volume  sio:SIO_000300 "#{pub.volume}" ;
#                               rdf:type cbgp:volume .

#                     }}

#   WRITE_PUB
#   DATABASE_UPDATE.update(publication)

#   affid = 0
#   pub.affiliations[0].each do |affiliation| # afils is a list of lists
#     affid += 1

#     publication = <<WRITE_AFFILS
#       #{PREFIXES}
#       PREFIX pub:  <http://admin.cbgp.upm.es/graphs/publications/#{pub.uniqid}#>
#       PREFIX pubgraph:  <hhttp://admin.cbgp.upm.es/graphs/publications/#{pub.uniqid}#>
#       INSERT DATA { GRAPH pub:container {
#             pubgraph:publication cbgp:has_affiliation pubgraph:affiliation_#{affid} .

#             pubgraph:affiliation_#{affid}  sio:SIO_000300 "#{affiliation}" ;
#                           rdf:type sio:SIO_000012 .  # organization
#       }}
# WRITE_AFFILS
#     DATABASE_UPDATE.update(publication)
#   end

#   authid = 0
#   pub.authors[0].each do |author| # authors is a list of lists
#     authid += 1

#     publication = <<WRITE_AUTHORS
#     #{PREFIXES}
#     PREFIX pub:  <http://admin.cbgp.upm.es/graphs/publications/#{pub.uniqid}#>
#     PREFIX pubgraph:  <hhttp://admin.cbgp.upm.es/graphs/publications/#{pub.uniqid}#>
#     INSERT DATA { GRAPH pub:container {
#           pubgraph:publication cbgp:has_author pubgraph:author_#{authid} .

#           pubgraph:author_#{authid}  sio:SIO_000300 "#{author.name}" ;
#                         sio:SIO_000671 pubgraph:author_#{authid}_id ;
#                         rdf:type ncit:NCIT_C42781 .  # Author
#           pubgraph:author_#{authid}_id sio:SIO_000300 "#{author.orcid}" ;
#                         cbgp:author_rank "#{author.rank}" ;
#                         rdf:type edam:data_4022 .  # ORCiD Identifier

#     }}
# WRITE_AUTHORS
#     DATABASE_UPDATE.update(publication)
#   end
# end

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
def write_dataset_to_db_query(dataset:, oldid: nil)
  database = dataset.form_type # e.g., the specific subtype of dataset  (member, project, etc.)
  primary_id  = dataset.primary_id # the unique identifier for this dataset instance
  warn "WRITE DATASET primary_id is #{primary_id}\n\n"

  # If this is an update (oldid present), delete the entire old named graph first
  if oldid
    # Old graph URI is constructed directly (no prefix, full URI string
    delete_dataset_query(oldid: "#{BASE_URI}#{database}/context/#{oldid}") # assumed method that runs DROP GRAPH or DELETE WHERE
  end

  # PREFIX bases:
  # - dataset:      points to the base URI for dataset nodes (ends with /dataset/uniqid>)
  # - datasetgraph: points to the base URI for named graphs (ends with /context/uniqid>)
  datasetPREFIX      = "<#{BASE_URI}#{database}/dataset/>"
  datasetgraphPREFIX = "<#{BASE_URI}#{database}/context/>"
  datasetFragmentPREFIX = "<#{BASE_URI}#{database}/dataset/#{primary_id}#>"

  triples = []
  # Core typing triples for the dataset node itself
  # PREFIX dataset: #{datasetPREFIX}
  # PREFIX datasetfrag: #{datasetFragmentPREFIX}
  # PREFIX datasetgraph: #{datasetgraphPREFIX}
  triples << "dataset:#{primary_id} rdf:type sio:SIO_000089 ;"
  triples << "   rdf:type cbgp:#{database} ;"
  triples << '   sio:SIO_000671 datasetfrag:primary_id .'
  triples << "   datasetfrag:primary_id sio:SIO_000300 \"#{primary_id}\" ;"
  triples << '           rdf:type sio:SIO_000115 . # identifier.'

  # Process each field defined in the questionnaire/schema
  dataset.fields.each do |field|
    # Skip if the dataset object doesn't have a getter method for this field
    next unless dataset.respond_to?(field[:method])

    value = dataset.public_send(field[:method]) # actual value(s) from the dataset object

    # Skip completely if nil or an empty array
    next if value.nil? || (value.is_a?(Array) && value.empty?)

    questionclass = field[:questionclass] # the specific property/class name for this field

    # Helper to properly escape a value for a SPARQL string literal:
    # - Always convert to string first (fixes the error when value is Date, Integer, etc.)
    # - Escape backslashes first, then double quotes (standard order)
    # - This produces safe "literal" content
    escape_for_literal = ->(v) { v.to_s.gsub('\\', '\\\\').gsub('"', '\\"') }

    if field[:cardinality] == 'Multiple' && value.is_a?(Array)
      # Multi-valued field: one reified attribute per array item
      value.each_with_index do |val, index|
        # Skip empty/whitespace-only items (after converting to string)
        next if val.to_s.strip.empty?

        # Build a unique URI for this specific attribute instance
        # (removes < > from prefix → clean base, then appends ID + field + index)
        this_attribute = "#{datasetPREFIX.gsub(/[<>]/, '')}#{primary_id}/#{questionclass}_#{index + 1}"

        triples << "dataset:#{primary_id} sio:SIO_000008 <#{this_attribute}> ."
        triples << "<#{this_attribute}> rdf:type cbgp:#{questionclass} ."
        triples << "<#{this_attribute}> sio:SIO_000300 \"#{escape_for_literal.call(val)}\" ."
      end
    else
      # Single-valued field
      # Optional improvement: skip if the string value is blank (consistent with multi-valued)
      # (Uncomment if you want to avoid inserting empty literals)
      # next if value.to_s.strip.empty?

      # Build URI for the single attribute
      this_attribute = "#{datasetPREFIX.gsub(/[<>]/, '')}#{primary_id}/#{questionclass}"

      triples << "dataset:#{primary_id} sio:SIO_000008 <#{this_attribute}> ."
      triples << "<#{this_attribute}> rdf:type cbgp:#{questionclass} ."
      triples << "<#{this_attribute}> sio:SIO_000300 \"#{escape_for_literal.call(value)}\" ."
    end
  end

  # Join all triples into the GRAPH body
  body = triples.join("\n")

  # Full SPARQL UPDATE query with prefixes and INSERT DATA into the named graph
  <<~WRITE_DATASET
    #{PREFIXES}
    PREFIX dataset: #{datasetPREFIX}
    PREFIX datasetfrag: #{datasetFragmentPREFIX}
    PREFIX datasetgraph: #{datasetgraphPREFIX}
    INSERT DATA { GRAPH datasetgraph:#{primary_id} {
    #{body}
    }}
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
