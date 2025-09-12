# frozen_string_literal: true

require "linkeddata"
require "sparql"
require "sparql/client"

host = GRAPHDB_HOST || "localhost:7200"
user = GRAPHDB_USER || "cbgp"
pass = GRAPHDB_PASS || "cbgp"

ONTOLOGY = RDF::Repository.load(CBGP_KB)  # set in configuration.rb and/or in docker-compose
PUBLICATIONS = SPARQL::Client.new("http://#{GRAPHDB_USER}:#{GRAPHDB_PASS}@#{host}/repositories/publications")
PUBLICATIONS_UPDATE = SPARQL::Client.new("http://#{GRAPHDB_USER}:#{GRAPHDB_PASS}@#{host}/repositories/publications/statements")
PROJECTS = SPARQL::Client.new("http://#{GRAPHDB_USER}:#{GRAPHDB_PASS}@#{host}/repositories/projects")
PROJECTS_UPDATE = SPARQL::Client.new("http://#{GRAPHDB_USER}:#{GRAPHDB_PASS}@#{host}/repositories/projects/statements")
PERSONNEL = SPARQL::Client.new("http://#{GRAPHDB_USER}:#{GRAPHDB_PASS}@#{host}/repositories/personnel")
PERSONNEL_UPDATE = SPARQL::Client.new("http://#{GRAPHDB_USER}:#{GRAPHDB_PASS}@#{host}/repositories/personnel/statements")

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

def get_questionnaire_types(language: 'en')
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
  results = qs.execute(ONTOLOGY)
  results.map { |r| r.to_h.transform_values(&:to_s) } # https://w3id.org/CBGP-App#add-member => "Add/Edit Member"
end


def get_questionnaire_sections_query(questionnaire_type:, language: 'en')
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
  qs.execute(ONTOLOGY)
end

def get_section_questions_query(sectionid:, language: 'en')
  qs = <<GET_SECTION_QUESTIONS
    #{PREFIXES}

    SELECT ?q (str(?qlab) as ?label) ?widget ?class ?method ?cardinality ?answers ?sequence WHERE {
    ?q rdfs:subClassOf cbgp:#{sectionid} .
    ?q rdfs:label ?qlab .
    FILTER (lang(?qlab) = "#{language}")
    ?q local:widget-type ?widget .
    ?q local:widget-cardinality ?cardinality .
    ?q local:answer-block ?answers .
    OPTIONAL {?q local:object-class ?class }.
    ?q local:method ?method .
    ?q local:question-order ?sequence .
  } ORDER BY ?sequence

GET_SECTION_QUESTIONS
  qs = SPARQL.parse(qs)
  qs.execute(ONTOLOGY)
end

def get_answer_block_query(ablockid:, language: 'en')
  a = <<GET_ANSWER_BLOCK
    #{PREFIXES}

    SELECT DISTINCT ?aid ?label ?sequence WHERE {
      ?aid rdfs:subClassOf cbgp:#{ablockid} .
      ?aid rdfs:label ?label .
      FILTER (lang(?label) = "#{language}")
      ?aid local:answer-order ?sequence .
    } ORDER BY ?sequence
GET_ANSWER_BLOCK
warn "ANSWERBLOCK QUERY IS #{a}"

  a = SPARQL.parse(a)
  a.execute(ONTOLOGY)
end

def get_label_for_questionnaire_type(id:, language: 'en')
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

  res = lab.execute(ONTOLOGY)
  [res.first[:plabel].to_s, res.first[:label].to_s]
end

def get_label_for_id(id:, language: 'en')
  lab = SPARQL.parse("
    #{PREFIXES}

    SELECT ?label WHERE {
      cbgp:#{id} rdfs:label ?label .
      FILTER (lang(?label) = '#{language}')
    }
          ")

  res = lab.execute(ONTOLOGY)
  res.first[:label].to_s
end

def field_query(fieldid:, language: 'en')
  field = SPARQL.parse("
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
          ")
  field.execute(ONTOLOGY)
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
  PUBLICATIONS.query(publication)
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
  PUBLICATIONS.query(publication)
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
  PUBLICATIONS.query(retpub)
end

def delete_pub_query(pubid:)
  delete = <<DELETE_PUB
  DROP GRAPH <#{pubid}>

DELETE_PUB
  PUBLICATIONS_UPDATE.update(delete)
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
  PUBLICATIONS_UPDATE.update(publication)

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
    PUBLICATIONS_UPDATE.update(publication)
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
    PUBLICATIONS_UPDATE.update(publication)
  end



###################### Projects ##################
###################### Projects ##################
###################### Projects ##################
###################### Projects ##################
###################### Projects ##################
###################### Projects ##################

  def retrieve_project_core_query(doi:, graph:)
    # project = <<~READ
    #         #{PREFIXES}

    #   SELECT   ?doi ?scopusq ?scopusd1 ?oa ?sochoa ?pubtype ?title ?date ?journal ?volume
    #   WHERE{ GRAPH <#{graph}> {
    #               ?publicationn rdf:type sio:SIO_000087 ;  # n equates to "node", without n is "value"
    #                   sio:SIO_000671 ?idn ;
    #                   cbgp:has_scopus_q ?scopusqn ;
    #                   cbgp:has_scopus_d ?scopusd1n ;
    #                   cbgp:is_open_access ?oan ;
    #                   cbgp:has_so_acknowledgement ?sochoan ;
    #                   cbgp:cbgp_corresponding ?cbgp_correspondingn ;
    #                   cbgp:is_publication_type ?pubtypen ;
    #                   cbgp:has_title ?titlen ;
    #                   cbgp:has_volume ?volumen ;
    #                   cbgp:has_publication_year ?yearn ;
    #                   cbgp:is_published_in ?journaln .

    #               ?idn  sio:SIO_000300 ?doi ;
    #                             rdf:type sio:SIO_000115 ;
    #                             rdf:type edam:data_1188 .

    #               ?scopusqn  sio:SIO_000300 ?scopusq ;
    #                             rdf:type cbgp:scopusq .

    #               ?scopusd1n  sio:SIO_000300 ?scopusd1 ;
    #                             rdf:type cbgp:scopusd1 .

    #               ?oan  sio:SIO_000300 ?oa ;
    #                             rdf:type cbgp:oa .

    #               ?sochoan  sio:SIO_000300 ?sochoa ;
    #                             rdf:type cbgp:sochoa .

    #               ?cbgp_correspondingn  sio:SIO_000300 ?cbgp_corresponding ;
    #                             rdf:type cbgp:cbgp_corresponding .

    #               ?pubtypen  sio:SIO_000300 ?pubtype ;
    #                             rdf:type cbgp:pubtype .

    #               ?titlen  sio:SIO_000300 ?title ;
    #                             rdf:type cbgp:title .

    #               ?daten  sio:SIO_000300 ?date ;
    #                             rdf:type sio:SIO_001314 .

    #               ?journaln  sio:SIO_000300 ?journal ;
    #                             rdf:type cbgp:journal ;
    #                             rdf:type obo:GSSO_004587 .

    #               ?volumen  sio:SIO_000300 ?volume ;
    #                             rdf:type cbgp:volume .

    #                   }}

    # READ
    # PUBLICATIONS.query(publication)
  end
end
