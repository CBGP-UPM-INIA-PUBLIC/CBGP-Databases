# frozen_string_literal: true

require 'linkeddata'
require 'sparql'
require 'sparql/client'

host = "localhost:7200"
ONTOLOGY = RDF::Repository.load('https://w3id.org/CBGP-App#')
PUBLICATIONS = SPARQL::Client.new("http://cbgp:cbgp@#{host}/repositories/publications")
PUBLICATIONS_UPDATE = SPARQL::Client.new("http://cbgp:cbgp@#{host}/repositories/publications/statements")

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


def get_questionnaire_sections_query(questionnaire_type:)
  # questionnaire_type = Add/Edit publications (#add-publication) has-fields Publication Questions (#new-publication-questions)

  qs = <<GET_CATEGORY_SECTIONS
    #{PREFIXES}

    SELECT ?sec (str(?seclab) as ?label)  WHERE {
      cbgp:#{questionnaire_type} local:has-fields ?sec .
      ?sec rdfs:label ?seclab .
    }
GET_CATEGORY_SECTIONS
qs = SPARQL.parse(qs)
qs.execute(ONTOLOGY)
end

def get_section_questions_query(sectionid:) # sectionid  must be just teh ID
  qs = <<GET_SECTION_QUESTIONS
    #{PREFIXES}

    SELECT ?q (str(?qlab) as ?label) ?widget ?class ?method ?cardinality ?answers ?sequence  WHERE {
    ?q rdfs:subClassOf cbgp:#{sectionid} .
    ?q rdfs:label ?qlab .
    ?q local:widget-type ?widget .
    ?q local:widget-cardinality ?cardinality .
    ?q local:answer-block ?answers .
    ?q local:object-class ?class .
    ?q local:object-method ?method .
    ?q local:question-order ?sequence .
  } order by ?sequence

GET_SECTION_QUESTIONS
qs = SPARQL.parse(qs)
res = qs.execute(ONTOLOGY)
res
end

def get_answer_block_query(ablockid:)
  a = <<GET_ANSWER_BLOCK
    #{PREFIXES}

  SELECT DISTINCT ?aid ?label ?sequence WHERE {
      ?aid rdfs:subClassOf cbgp:#{ablockid} .
      ?aid rdfs:label ?label .
      ?aid local:answer-order ?sequence .
  } ORDER BY ?sequence
GET_ANSWER_BLOCK
a = SPARQL.parse(a)
a.execute(ONTOLOGY)
end

def get_label_for_questionnaire_type(id:)
  lab = SPARQL.parse("
    #{PREFIXES}

    select ?plabel ?label where {
    cbgp:#{id} rdfs:label ?label ;
                 rdfs:subClassOf ?parent .
          ?parent rdfs:label ?plabel

    }
          ")

  res = lab.execute(ONTOLOGY)
  [res.first[:plabel].to_s, res.first[:label].to_s]
end

def get_label_for_id(id:)
  lab = SPARQL.parse("
    #{PREFIXES}

    select ?label where {
      		cbgp:#{id} rdfs:label ?label .
    }
          ")

  res = lab.execute(ONTOLOGY)
  res.first[:label].to_s
end


###################### Publications ##################
###################### Publications ##################
###################### Publications ##################
###################### Publications ##################
###################### Publications ##################
###################### Publications ##################

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
  pubexists = SPARQL.parse(retpub)  # validate query or die
  PUBLICATIONS.query(retpub)
end


def delete_pub_query(pubid:)

  delete = <<DELETE_PUB
  PREFIX pub:  <http://admin.cbgp.upm.es/graphs/publications/#{pubid}#>
  DROP GRAPH pub:container

DELETE_PUB
PUBLICATIONS_UPDATE.update(delete)
end

def write_pub_to_db_query(pub:)
  delete_pub_query(pubid: pub.uniqid)
  publication = <<WRITE_PUB
      #{PREFIXES}

PREFIX pub:  <http://admin.cbgp.upm.es/graphs/publications/#{pub.uniqid}#>
PREFIX pubgraph:  <hhttp://admin.cbgp.upm.es/graphs/publications/#{pub.uniqid}#>

INSERT DATA { GRAPH pub:container { 
            pubgraph:publication rdf:type sio:SIO_000087 ;  # publication 
                sio:SIO_000671 pubgraph:id ;
                cbgp:has_scopus_q pubgraph:scopusq ;
                cbgp:has_scopus_d pubgraph:scopusd1 ;
                cbgp:is_open_access pubgraph:oa ;
                cbgp:has_so_acknowledgement pubgraph:sochoa ;
                cbgp:is_publication_type pubgraph:pubtype ;
                cbgp:has_title pubgraph:title ;
                cbgp:has_title pubgraph:journal ;
                cbgp:has_title pubgraph:volume ;
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
    pub.affiliations[0].each do |affiliation|  # afils is a list of lists
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
                        rdf:type edam:data_4022 .  # ORCiD Identifier

    }}
WRITE_AUTHORS
    PUBLICATIONS_UPDATE.update(publication)
  end
end