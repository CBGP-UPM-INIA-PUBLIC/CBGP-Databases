# frozen_string_literal: true

require 'linkeddata'
require 'sparql'
require 'sparql/client'

ONTOLOGY= RDF::Repository.load('https://w3id.org/CBGP-App#')


def get_form_fields_query(form: "publication", lang: "EN")
  fields = SPARQL.parse(
    "  
  PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
  PREFIX sio: <http://semanticscience.org/resource/>
  PREFIX cbgp-local: <urn:cbgp-local:>

  SELECT ?field ?label ?widget ?cardinality WHERE 
    {
    <https://w3id.org/CBGP-App#add-#{form}> cbgp-local:has-fields ?fields . 
    ?field rdfs:subClassOf ?fields . 
    ?field rdfs:label ?label .
    ?field cbgp-local:widget-cardinality ?cardinality .
    ?field cbgp-local:widget-types ?widget . 
    # FILTER langMatches( lang(?label), '#{lang}')
    
    }")
  fields.execute(ONTOLOGY)
end
  


def get_answer_block_query(ablockid:, lang: "EN")
  a = <<GET_ANSWER_BLOCK
  prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
  prefix accv: <https://world-duchenne-organization.github.io/Accredited-Duchenne-Centers/vocabularies/accredited-questionnaire.owl#>
  prefix xml:<http://www.w3.org/XML/1998/namespace>
  prefix xsd:<http://www.w3.org/2001/XMLSchema#>
  prefix rdfs:<http://www.w3.org/2000/01/rdf-schema#>
  PREFIX onto: <http://www.ontotext.com/>
  PREFIX sio: <http://semanticscience.org/resource/>
  PREFIX local: <urn:local:>
  
  SELECT DISTINCT ?aid ?label ?sequence ?widget WHERE {
      ?aid rdfs:subClassOf accv:#{ablockid} .
      ?aid rdfs:label ?label .
      ?aid local:answerorder ?sequence .
      ?aid local:widget ?widget .
      FILTER langMatches( lang(?label), '#{lang}')
  } ORDER BY ?sequence
GET_ANSWER_BLOCK
  ONTOLOGY.query(a)
end



################################################
###  CENTERS
##############################################

def delete_center_query(centerid:)

  delete = <<DELETE_CENTER
  PREFIX center:  <http://accredited.worldduchenne.org/vocabularies/centers/#{centerid}#>
  DROP GRAPH center:container  

DELETE_CENTER
CENTERS_UPDATE.update(delete)
end


def write_center_to_db(center:)
  delete_center_query(centerid: center.id)
  center = <<WRITE_CENTER
PREFIX acc: <https://world-duchenne-organization.github.io/Accredited-Duchenne-Centers/vocabularies/accredited-questionnaire.owl#>
PREFIX accv: <https://world-duchenne-organization.github.io/Accredited-Duchenne-Centers/vocabularies/accredited-questionnaire.owl#>
PREFIX owl: <http://www.w3.org/2002/07/owl#>
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX xml:<http://www.w3.org/XML/1998/namespace>
PREFIX xsd:<http://www.w3.org/2001/XMLSchema#>
PREFIX rdfs:<http://www.w3.org/2000/01/rdf-schema#>
PREFIX onto: <http://www.ontotext.com/>
PREFIX sio: <http://semanticscience.org/resource/>
PREFIX schema: <http://schema.org/>
PREFIX centergraph:  <http://accredited.worldduchenne.org/vocabularies/centers/#{center.id}/>
PREFIX center:  <http://accredited.worldduchenne.org/vocabularies/centers/#{center.id}#>
PREFIX local: <urn:local:>

INSERT DATA { GRAPH center:container { 
  centergraph:center rdf:type schema:Organization; 
                schema:email "#{center.email}";
                schema:name "#{center.name}";
                rdfs:label "#{center.name}";
                schema:address "#{center.country}";
                schema:status "#{center.status}" ;
                local:visibility "#{center.visibility}" ;

                schema:contactPoint center:contact .
  center:contact schema:name "#{center.applicant}" ;
                rdfs:type schema:ContactPoint .
}}

WRITE_CENTER
  CENTERS_UPDATE.update(center)
end
