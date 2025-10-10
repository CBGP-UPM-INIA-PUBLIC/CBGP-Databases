# frozen_string_literal: true

require 'linkeddata'
require 'sparql'
require 'sparql/client'

host = GRAPHDB_HOST || 'localhost:7200'
GRAPHDB_USER || 'cbgp'
GRAPHDB_PASS || 'cbgp'
GRAPHDB_DBNAME || "kbdatabase"

$ontology = RDF::Repository.load(CBGP_KB) # set in configuration.rb and/or in docker-compose
DATABASE = SPARQL::Client.new("http://#{GRAPHDB_USER}:#{GRAPHDB_PASS}@#{host}/repositories/#{GRAPHDB_DBNAME}")
DATABASE_UPDATE = SPARQL::Client.new("http://#{GRAPHDB_USER}:#{GRAPHDB_PASS}@#{host}/repositories/#{GRAPHDB_DBNAME}/statements")

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
      cbgp:#{questionnaire_type} local:has-fields ?sec . # "add-publications", "add-project", "add-member"
      ?sec rdfs:label ?seclab .
      FILTER (lang(?seclab) = "#{language}")
    }
GET_QUESTIONNAIRE_SECTIONS
  warn "QUERY IS #{qs}"
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

  warn "HIERARCHICAL ANSWERBLOCK QUERY IS #{query}"
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
  warn "FIELD QUERY is #{query}"
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

def retrieve_publication_core_query(doi:, graph:)
  publication = <<~READ_PUB
          #{PREFIXES}

    SELECT   ?doi ?scopusq ?scopusd1 ?oa ?sochoa ?pubtype ?title ?date ?journal ?volume
    WHERE{ GRAPH <#{graph}> {
                ?publicationn rdf:type sio:SIO_000087 ;  # n equates to "node", without n is "value"
                    sio:SIO_000671 ?idn ;
                    cbgp:has_scopus_q ?scopusqn ;
                    cbgp:has_scopus_d ?scopusd1n ;
                    cbgp:is_open_access ?oan ;
                    cbgp:has_so_acknowledgement ?sochoan ;
                    cbgp:cbgp_corresponding ?cbgp_correspondingn ;
                    cbgp:is_publication_type ?pubtypen ;
                    cbgp:has_title ?titlen ;
                    cbgp:has_volume ?volumen ;
                    cbgp:has_publication_year ?yearn ;
                    cbgp:is_published_in ?journaln .

                ?idn  sio:SIO_000300 ?doi ;
                              rdf:type sio:SIO_000115 ;
                              rdf:type edam:data_1188 .

                ?scopusqn  sio:SIO_000300 ?scopusq ;
                              rdf:type cbgp:scopusq .

                ?scopusd1n  sio:SIO_000300 ?scopusd1 ;
                              rdf:type cbgp:scopusd1 .

                ?oan  sio:SIO_000300 ?oa ;
                              rdf:type cbgp:oa .

                ?sochoan  sio:SIO_000300 ?sochoa ;
                              rdf:type cbgp:sochoa .

                ?cbgp_correspondingn  sio:SIO_000300 ?cbgp_corresponding ;
                              rdf:type cbgp:cbgp_corresponding .

                ?pubtypen  sio:SIO_000300 ?pubtype ;
                              rdf:type cbgp:pubtype .

                ?titlen  sio:SIO_000300 ?title ;
                              rdf:type cbgp:title .

                ?daten  sio:SIO_000300 ?date ;
                              rdf:type sio:SIO_001314 .

                ?journaln  sio:SIO_000300 ?journal ;
                              rdf:type cbgp:journal ;
                              rdf:type obo:GSSO_004587 .

                ?volumen  sio:SIO_000300 ?volume ;
                              rdf:type cbgp:volume .

                    }}

  READ_PUB
  PUBLICATIONS.query(publication)
end

def retrieve_publication_affils_query(doi:, graph:)
  publication = <<READ_AFFILS
    #{PREFIXES}
    SELECT ?affiliation
    WHERE { GRAPH <#{graph}> {
          ?publication cbgp:has_affiliation ?affiliationn .

          ?affiliationn  sio:SIO_000300 ?affiliation ;
                        rdf:type sio:SIO_000012 .  # organization
    }}
READ_AFFILS
  DATABASE.query(publication)
end

def retrieve_publication_auths_query(doi:, graph:)
  publication = <<READ_AUTHORS
  #{PREFIXES}
  SELECT ?name ?orcid ?rank
  WHERE { GRAPH <#{graph}> {
        ?publication cbgp:has_author ?authorn .

        ?authorn  sio:SIO_000300 ?name ;
                      sio:SIO_000671 ?authidn ;
                      rdf:type ncit:NCIT_C42781 .  # Author
        ?authidn sio:SIO_000300 ?orcid ;
                      rdf:type edam:data_4022 ; # ORCiD Identifier
                      cbgp:author_rank ?rank.

  }}
READ_AUTHORS
  warn "publication is: \n\n #{publication}\n\n"
  DATABASE.query(publication)
end

def retrieve_pub_graph_query(doi:)
  retpub = <<SELECT_PUB
        #{PREFIXES}
  select ?g where {
  graph ?g {
      ?pub sio:SIO_000671 ?id .

      ?id  sio:SIO_000300 "#{doi}" ;
        rdf:type sio:SIO_000115 ; # identifier
        rdf:type edam:data_1188 . # doi
  }}

SELECT_PUB
  # pubexists = SPARQL.parse(retpub)  # validate query or die
  DATABASE.query(retpub)
end

def delete_pub_query(pubid:)
  delete = <<DELETE_PUB
  DROP GRAPH <#{pubid}>

DELETE_PUB
  DATABASE_UPDATE.update(delete)
end

def write_pub_to_db_query(pub:, oldid: nil)
  delete_pub_query(pubid: oldid) if oldid
  publication = <<~WRITE_PUB
          #{PREFIXES}

    PREFIX pub:  <http://admin.cbgp.upm.es/graphs/publications/#{pub.uniqid}#>
    PREFIX pubgraph:  <hhttp://admin.cbgp.upm.es/graphs/publications/#{pub.uniqid}#>

    INSERT DATA { GRAPH pub:container {
                pubgraph:publication rdf:type sio:SIO_000087 ;  # publication
                    sio:SIO_000671 pubgraph:id ;
                    cbgp:has_scopus_q pubgraph:scopusq ;
                    cbgp:has_scopus_d pubgraph:scopusd1 ;
                    cbgp:is_open_access pubgraph:oa ;
                    cbgp:cbgp_corresponding pubgraph:cbgp_corresponding ;
                    cbgp:has_so_acknowledgement pubgraph:sochoa ;
                    cbgp:is_publication_type pubgraph:pubtype ;
                    cbgp:has_title pubgraph:title ;
                    cbgp:has_journal pubgraph:journal ;
                    cbgp:has_volume pubgraph:volume ;
                    cbgp:has_publication_year pubgraph:year ;
                    cbgp:is_published_in pubgraph:journal .
                pubgraph:id  sio:SIO_000300 "#{pub.doi}" ;
                              rdf:type sio:SIO_000115 ; # identifier
                              rdf:type edam:data_1188 . # doi

                pubgraph:scopusq  sio:SIO_000300 "#{pub.scopusq}" ;
                              rdf:type cbgp:scopusq .

                pubgraph:scopusd1  sio:SIO_000300 "#{pub.scopusd1}" ;
                              rdf:type cbgp:scopusd1 .

                pubgraph:oa  sio:SIO_000300 "#{pub.oa}" ;
                              rdf:type cbgp:oa .

                pubgraph:sochoa  sio:SIO_000300 "#{pub.sochoa}" ;
                              rdf:type cbgp:sochoa .

                pubgraph:cbgp_corresponding  sio:SIO_000300 "#{pub.cbgp_corresponding}" ;
                              rdf:type cbgp:cbgp_corresponding .

                pubgraph:pubtype  sio:SIO_000300 "#{pub.pubtype}" ;
                              rdf:type cbgp:pubtype .

                pubgraph:title  sio:SIO_000300 "#{pub.title}" ;
                              rdf:type cbgp:title .

                pubgraph:date  sio:SIO_000300 "#{pub.date}" ;
                              rdf:type sio:SIO_001314 .  # date of issue

                pubgraph:journal  sio:SIO_000300 "#{pub.journal}" ;
                              rdf:type cbgp:journal ;
                              rdf:type obo:GSSO_004587 .

                pubgraph:volume  sio:SIO_000300 "#{pub.volume}" ;
                              rdf:type cbgp:volume .

                    }}

  WRITE_PUB
  DATABASE_UPDATE.update(publication)

  affid = 0
  pub.affiliations[0].each do |affiliation| # afils is a list of lists
    affid += 1

    publication = <<WRITE_AFFILS
      #{PREFIXES}
      PREFIX pub:  <http://admin.cbgp.upm.es/graphs/publications/#{pub.uniqid}#>
      PREFIX pubgraph:  <hhttp://admin.cbgp.upm.es/graphs/publications/#{pub.uniqid}#>
      INSERT DATA { GRAPH pub:container {
            pubgraph:publication cbgp:has_affiliation pubgraph:affiliation_#{affid} .

            pubgraph:affiliation_#{affid}  sio:SIO_000300 "#{affiliation}" ;
                          rdf:type sio:SIO_000012 .  # organization
      }}
WRITE_AFFILS
    DATABASE_UPDATE.update(publication)
  end

  authid = 0
  pub.authors[0].each do |author| # authors is a list of lists
    authid += 1

    publication = <<WRITE_AUTHORS
    #{PREFIXES}
    PREFIX pub:  <http://admin.cbgp.upm.es/graphs/publications/#{pub.uniqid}#>
    PREFIX pubgraph:  <hhttp://admin.cbgp.upm.es/graphs/publications/#{pub.uniqid}#>
    INSERT DATA { GRAPH pub:container {
          pubgraph:publication cbgp:has_author pubgraph:author_#{authid} .

          pubgraph:author_#{authid}  sio:SIO_000300 "#{author.name}" ;
                        sio:SIO_000671 pubgraph:author_#{authid}_id ;
                        rdf:type ncit:NCIT_C42781 .  # Author
          pubgraph:author_#{authid}_id sio:SIO_000300 "#{author.orcid}" ;
                        cbgp:author_rank "#{author.rank}" ;
                        rdf:type edam:data_4022 .  # ORCiD Identifier

    }}
WRITE_AUTHORS
    DATABASE_UPDATE.update(publication)
  end
end

###################### DATASET ##################
###################### DATASET ##################
###################### DATASET ##################
###################### DATASET ##################
###################### DATASET ##################
###################### DATASET ##################
###################### DATASET ##################
###################### DATASET ##################

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

  warn "retrieve dataset graph query is: #{retds}"
  # pubexists = SPARQL.parse(retpub)  # validate query or die
  DATABASE.query(retds)
end

def delete_dataset_query(oldid:)
  delete = <<DELETE_DATASET
  DROP GRAPH <#{oldid}>

DELETE_DATASET
  DATABASE_UPDATE.update(delete)
end

def write_dataset_to_db(dataset:, oldid: nil)
  writequery = write_dataset_to_db_query(dataset: dataset, oldid: oldid)
  warn "\n\n\n\n#{writequery}\n\n\n"
  DATABASE_UPDATE.update(writequery)
end

def write_dataset_to_db_query(dataset:, oldid: nil)
  delete_dataset_query(oldid: oldid) if oldid

  datasettype = dataset.form_type
  primary_id = dataset.primary_id

  # Build the triples
  main_subject = 'dataset:dataset'
  main_triples = ["#{main_subject} rdf:type sio:SIO_000089 ;"]

  attribute_triples = []

  # Handle primary identifier specially
  primary_field = dataset.fields.find { |f| f[:is_primary] }
  primary_value = primary_id # Default to dataset.primary_id
  primary_questionclass = 'primary_id'
  primary_type = 'sio:SIO_000115' # Default type for identifier

  if primary_field
    primary_questionclass = primary_field[:questionclass]
    primary_method = primary_field[:method]
    primary_value = dataset.send(primary_method) if primary_method && dataset.respond_to?(primary_method)
    primary_type = primary_field[:answers] || primary_field[:class] || primary_type
  end

  primary_node = "datasetgraph:#{primary_questionclass}"
  primary_predicate = 'sio:SIO_000671' # has identifier

  main_triples << "  #{primary_predicate} #{primary_node} ;"

  attribute_triples << "  #{primary_node} sio:SIO_000300 \"#{primary_value}\" ;" # has value
  attribute_triples << "    rdf:type #{primary_type} ."

  # Handle other fields
  dataset.fields.each do |field|
    next if field[:is_primary]

    questionclass = field[:questionclass]
    method_name = field[:method]
    next unless dataset.respond_to?(method_name)

    value = dataset.send(method_name)
    next if value.nil? || value.to_s.empty?

    # Assume cardinality is 1 for simplicity; handle arrays if needed in future
    predicate = "<#{field[:q]}>" # Use full URI for predicate

    node = "datasetgraph:#{questionclass}"

    type = field[:answers] || field[:class] || "cbgp:#{questionclass}"

    main_triples << "  #{predicate} #{node} ;"

    attribute_triples << "  #{node} sio:SIO_000300 \"#{value}\" ;"
    attribute_triples << "    rdf:type #{type} ."
  end

  # Replace the last semicolon in main_triples with a period
  main_triples[-1].sub!(/ ;$/, ' .')

  # Join the triples
  body = main_triples.join("\n") + "\n" + attribute_triples.join("\n")

  # Build the full SPARQL query
  <<~WRITE_DATASET
        #{PREFIXES}

        PREFIX dataset: <http://admin.cbgp.upm.es/graphs/datasets/#{datasettype}/#{primary_id}#>
        PREFIX datasetgraph: <http://admin.cbgp.upm.es/graphs/datasets/#{datasettype}/#{primary_id}#>

        INSERT DATA { GRAPH datasetgraph:container {
    #{body}
        }}
  WRITE_DATASET
end

def build_search_query(search_params:, dataset_type:)
  # Validate input
  return nil unless search_params.is_a?(Hash) && !search_params.empty?

  # Base SPARQL query structure
  query = <<~SPARQL
    #{PREFIXES}
    PREFIX datasetgraph: <http://admin.cbgp.upm.es/graphs/datasets/#{dataset_type}/>

    SELECT DISTINCT ?dataset
    WHERE {
  SPARQL

  # Dynamic conditions based on search parameters
  conditions = []
  search_params.each do |method_name, value|
    # Convert method name to URI (e.g., "contract_type" -> "cbgp:contract_type")
    predicate = "cbgp:#{method_name}"
    field_node = "datasetgraph:#{method_name}"

    # Add condition for the field value
    conditions << <<-CONDITION
      GRAPH ?dataset {
        ?dataset #{predicate} #{field_node} .
        #{field_node} sio:SIO_000300 "#{value}" .
        #{field_node} rdf:type ?field_type .
      }
    CONDITION
  end

  # Join conditions with AND logic (implicit in SPARQL GRAPH clauses)
  query += conditions.join("\n")

  # Close the query with dataset type filter
  query += <<~SPARQL
      # Ensure graphs are from the specified dataset type
      FILTER (STRSTARTS(STR(?dataset), "http://admin.cbgp.upm.es/graphs/datasets/#{dataset_type}/"))
    }
    ORDER BY ?dataset
  SPARQL

  warn "Generated search query: #{query}"
  query
end

def execute_search(search_params:, dataset_type:)
  query = build_search_query(search_params: search_params, dataset_type: dataset_type)
  return [] unless query

  results = DATABASE.query(query)
  results.map { |result| result[:dataset].to_s } # Return array of graph URIs
end

# Example usage (to be
