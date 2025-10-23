# frozen_string_literal: true

require 'linkeddata'
require 'sparql'
require 'sparql/client'

host = GRAPHDB_HOST || 'localhost:7200'
GRAPHDB_USER || 'cbgp'
GRAPHDB_PASS || 'cbgp'
GRAPHDB_DBNAME || 'kbdatabase'

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

  #  warn "LABEL QUERY FOR #{id}: #{query}"
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

  warn "retrieve dataset graph query is:\n #{retds}"
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
  warn "WRITE DATASET QUERY\n#{writequery}\n\n\n"
  # abort
  DATABASE_UPDATE.update(writequery)
end

def write_dataset_to_db_query(dataset:, oldid: nil)
  datasettype = dataset.form_type
  primary_id = dataset.primary_id

  if oldid
    oldgraph = "http://admin.cbgp.upm.es/graphs/datasets/#{datasettype}/context/#{oldid}"
    delete_dataset_query(oldid: oldgraph)
  end

  datasetPREFIX = "<http://admin.cbgp.upm.es/graphs/datasets/#{datasettype}/dataset/>"
  datasetgraphPREFIX = "<http://admin.cbgp.upm.es/graphs/datasets/#{datasettype}/context/>"

  triples = []
  triples << "dataset:#{primary_id} rdf:type sio:SIO_000089 ;"
  triples << "   rdf:type cbgp:#{datasettype} ;"
  triples << "   sio:SIO_000671 \"#{primary_id}\" ."

  dataset.fields.each do |field|
    next unless dataset.respond_to?(field[:method])

    value = dataset.public_send(field[:method])
    next if value.nil? || (value.is_a?(Array) && value.empty?)

    questionclass = field[:questionclass]
    if field[:cardinality] == 'multi' && value.is_a?(Array)
      value.each_with_index do |val, index|
        next if val.to_s.strip.empty?

        this_attribute = "#{datasetPREFIX.gsub(/[<>]/, '')}/#{primary_id}/#{questionclass}_#{index + 1}"
        triples << "dataset:#{primary_id} sio:SIO_000008 <#{this_attribute}> ."
        triples << "<#{this_attribute}> rdf:type cbgp:#{questionclass} ."
        triples << "<#{this_attribute}> sio:SIO_000300 \"#{val.gsub('"', '\"')}\" ."
      end
    else
      this_attribute = "#{datasetPREFIX.gsub(/[<>]/, '')}/#{primary_id}/#{questionclass}"
      triples << "dataset:#{primary_id} sio:SIO_000008 <#{this_attribute}> ."
      triples << "<#{this_attribute}> rdf:type cbgp:#{questionclass} ."
      triples << "<#{this_attribute}> sio:SIO_000300 \"#{value.gsub('"', '\"')}\" ."
    end
  end

  body = triples.join("\n")
  <<~WRITE_DATASET
    #{PREFIXES}
    PREFIX dataset: #{datasetPREFIX}
    PREFIX datasetgraph: #{datasetgraphPREFIX}
    INSERT DATA { GRAPH datasetgraph:#{primary_id} {
    #{body}
    }}
  WRITE_DATASET
end

# def write_dataset_to_db_query(dataset:, oldid: nil)
#   datasettype = dataset.form_type
#   primary_id = dataset.primary_id

#   if oldid
#     oldgraph = "http://admin.cbgp.upm.es/graphs/datasets/#{datasettype}/context/#{oldid}"
#     delete_dataset_query(oldid: oldgraph)
#   end

#   datasetPREFIX =  "<http://admin.cbgp.upm.es/graphs/datasets/#{datasettype}/dataset/>"
#   datasetgraphPREFIX = "<http://admin.cbgp.upm.es/graphs/datasets/#{datasettype}/context/>"
#   #context = "datasetgraphPREFIX:#{primary_id}"

#   # subject_class = "cbgp:#{primary_questionclass}"  # cbgp:mem15  comes from the cbgp prefix which is the ontology base URI

#   # Build the triples

#   triples = []
#   triples << "dataset:#{primary_id} rdf:type sio:SIO_000089 ;  # sio dataset"  # sio:dataset
#   triples << "   rdf:type cbgp:#{datasettype} ;"  # cbgp:members

#   triples << "   sio:SIO_000671 \"#{primary_id}\" .  # has identifier"  # sio:has-identifier   ../admin.cbgp.../datasets/members/dataset/abc123/mem15

#   # Handle other fields

#   dataset.fields.each do |field|
#     # warn field.inspect + "\n\n\n"

#     questionclass = field[:questionclass]  # the class of each question, from the ontology   e.g. mem1  if it is cbgp:mem1
#     method = field[:method]
#     # warn "value is #{dataset.send(method.to_sym)}"
#     next unless dataset.respond_to?(method.to_sym)
#     value = dataset.send(method.to_sym)
#     next if value.nil? || value.to_s.empty?

#     this_attribute = datasetPREFIX.gsub(/[<>]/, "") + "/#{primary_id}/#{questionclass}"

#     triples << "dataset:#{primary_id} sio:SIO_000008 <#{this_attribute}> .  # has attribute" # has attribute
#     triples << "<#{this_attribute}> rdf:type cbgp:#{questionclass} ."
#     triples << "<#{this_attribute}> sio:SIO_000300 \"#{value}\" . # has value\n"
#   end

#   # Join the triples
#   body = triples.join("\n")

#   # Build the full SPARQL query
#   <<~WRITE_DATASET
#         #{PREFIXES}

#         PREFIX dataset: #{datasetPREFIX}
#         PREFIX datasetgraph: #{datasetgraphPREFIX}

#         INSERT DATA { GRAPH datasetgraph:#{primary_id} {
#     #{body}
#         }}
#   WRITE_DATASET
# end

# def build_search_query(search_params:, dataset_type:)
#   # Validate input: ensure at least one non-empty parameter
#   return nil unless search_params.is_a?(Hash) && search_params.any? do |k, v|
#     !v.nil? && ((!v.is_a?(Hash) && !v.to_s.strip.empty?) || (v.is_a?(Hash) && v.values.any? do |val|
#       !val.to_s.strip.empty?
#     end))
#   end

#   datasetPREFIX = "<http://admin.cbgp.upm.es/graphs/datasets/#{dataset_type}/dataset/>"
#   datasetgraphPREFIX = "<http://admin.cbgp.upm.es/graphs/datasets/#{dataset_type}/context/>"
#   # Base SPARQL query structure
#   query = <<~SPARQL
#     #{PREFIXES}
#     PREFIX dataset: #{datasetPREFIX}
#     PREFIX datasetgraph: #{datasetgraphPREFIX}

#     SELECT DISTINCT ?datasetgraph
#     WHERE {
#           GRAPH ?datasetgraph {

#   SPARQL

#   # Dynamic conditions based on search parameters
#   conditions = []
#   dates = {}
#   search_params.each do |questionclass, value|
#     warn "questionclass #{questionclass}  value #{value}"
#     # Skip empty or irrelevant values
#     next if value.nil? || (value.is_a?(String) && value.strip.empty?)
#     next if value.is_a?(Hash) && value.values.all? { |val| val.to_s.strip.empty? }

#     if value.is_a?(Hash) # this is a date range
#       start_date = value['start']&.strip
#       end_date = value['end']&.strip
#       next if start_date.to_s.empty? && end_date.to_s.empty? # Skip empty date ranges

#       # FILTER (?start >= "2023-01-01"^^xsd:date && ?start <= "2023-12-31"^^xsd:date)
#       filter = ''
#       if !start_date.to_s.empty? && !end_date.to_s.empty?
#         filter = "FILTER (?datevalue >= \"#{start_date}\"^^xsd:date && ?datevalue <= \"#{end_date}\"^^xsd:date) "
#       elsif !start_date.to_s.empty?
#         filter = "FILTER (?datevalue >= \"#{start_date}\"^^xsd:date) "
#       elsif !end_date.to_s.empty?
#         filter = "FILTER (?datevalue >= \"#{end_date}\"^^xsd:date) "
#       end

#       conditions << <<-CONDITION
#         ?dataset sio:SIO_000008 ?attribute .  # has attribute.
#         ?attribute sio:SIO_000300 ?datevalue .
#         ?attribute rdf:type cbgp:#{questionclass} .  # this is how we get the right attribute
#         #{filter} .

#       CONDITION
#     else
#       # Handle simple string fields (e.g., group_institution)
#       escaped_value = value.to_s.gsub('"', '\"')
#       conditions << <<-CONDITION
#         ?dataset sio:SIO_000008 ?attribute .  # has attribute.
#         ?attribute sio:SIO_000300 "#{escaped_value}" .
#         ?attribute rdf:type cbgp:#{questionclass} .  # this is how we get the right attribute

#       CONDITION
#     end
#   end

def build_search_query(search_params:, dataset_type:)
  return nil unless search_params.is_a?(Hash) && search_params.any? do |k, v|
    !v.nil? && ((!v.is_a?(Hash) && !v.to_s.strip.empty?) || (v.is_a?(Hash) && v.values.any? do |val|
      !val.to_s.strip.empty?
    end))
  end

  datasetPREFIX = "<http://admin.cbgp.upm.es/graphs/datasets/#{dataset_type}/dataset/>"
  datasetgraphPREFIX = "<http://admin.cbgp.upm.es/graphs/datasets/#{dataset_type}/context/>"
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
    else
      next if value.to_s.strip.empty?

      escaped_value = value.to_s.gsub('"', '\"')
      conditions << <<-CONDITION
        ?dataset sio:SIO_000008 ?attribute .
        ?attribute sio:SIO_000300 ?value .
        ?attribute rdf:type cbgp:#{questionclass} .
        FILTER(CONTAINS(LCASE(?value), LCASE("#{escaped_value}")))
      CONDITION
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

# def fetch_dataset_details(datasetgraph_uris, dataset_type)
#   return [] if datasetgraph_uris.empty?

#   fields = CBGP::Dataset.get_questionnaire_fields(questionnaire_type: dataset_type)
#   # :fieldid, :label, :answerblock, :answertree, :objectclass, :objectmethod, :questionorder, :cardinality, :widgettype

#   results = []

#   datasetgraph_uris.each do |uri|
#     # Build dynamic SPARQL query for all fields
#     select_clause = # creates a novel variable for each class e.g. ?mem1   ?mem5
#       fields.map do |f|
#         "?#{f[:fieldid]}"
#       end.join(' ')
#     where_clause = fields.map do |f|
#       <<~SPARQL
#         OPTIONAL {
#           ?dataset sio:SIO_000008 ?attribute#{f[:fieldid]} .
#           ?attribute#{f[:fieldid]} sio:SIO_000300 ?#{f[:fieldid]} .  # creates a novel variable for each class e.g. ?mem1   ?mem5
#           ?attribute#{f[:fieldid]} rdf:type cbgp:#{f[:fieldid]} .  # fieldid is the question class
#         }
#       SPARQL
#     end.join("\n")

#     query = <<~SPARQL
#       #{PREFIXES}
#       SELECT #{select_clause}
#       WHERE {
#         GRAPH <#{uri}> {
#           #{where_clause}
#         }
#       }
#     SPARQL

#     warn "Fetching details for dataset graph: #{uri}"
#     warn "Query: #{query}"
#     result = DATABASE.query(query).first
#     next unless result

#     details = { dataset: uri }
#     fields.each do |f|
#       value = result[f[:fieldid].to_sym]&.to_s
#       details[f[:fieldid].to_sym] = value
#     end
#     results << details
#   end

#   warn "Dataset details: #{results.inspect}"
#   results
# end
def fetch_dataset_details(datasetgraph_uris, dataset_type)
  return [] if datasetgraph_uris.empty?

  fields = CBGP::Dataset.get_questionnaire_fields(questionnaire_type: dataset_type)
  results = []

  datasetgraph_uris.each do |uri|
    select_clause = fields.map { |f| "?#{f[:fieldid]}" }.join(' ')
    where_clause = fields.map do |f|
      <<~SPARQL
        OPTIONAL {
          ?dataset sio:SIO_000008 ?attribute#{f[:fieldid]} .
          ?attribute#{f[:fieldid]} sio:SIO_000300 ?#{f[:fieldid]} .
          ?attribute#{f[:fieldid]} rdf:type cbgp:#{f[:fieldid]} .
        }
      SPARQL
    end.join("\n")

    query = <<~SPARQL
      #{PREFIXES}
      SELECT #{select_clause}
      WHERE {
        GRAPH <#{uri}> {
          #{where_clause}
        }
      }
    SPARQL

    result_set = DATABASE.query(query)
    details = { dataset: uri }
    fields.each do |f|
      if f[:cardinality] == 'multi'
        values = result_set.map { |r| r[f[:fieldid].to_sym]&.to_s }.compact.uniq
        details[f[:fieldid].to_sym] = values unless values.empty?
      else
        details[f[:fieldid].to_sym] = result_set.first & [f[:fieldid].to_sym]&.to_s
      end
    end
    results << details
  end

  warn "Dataset details: #{results.inspect}"
  results
end
# this is the end of the world as we know iii
