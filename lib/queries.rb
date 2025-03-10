# frozen_string_literal: true

require 'linkeddata'
require 'sparql'
require 'sparql/client'

ONTOLOGY = RDF::Repository.load('https://w3id.org/CBGP-App#')


def get_questionnaire_sections_query(questionnaire_type:)
  # questionnaire_type = Add/Edit publications (#add-publication) has-fields Publication Questions (#new-publication-questions)

  qs = <<GET_CATEGORY_SECTIONS
    prefix accv: <https://w3id.org/CBGP-App#>
    prefix owl: <http://www.w3.org/2002/07/owl#>
    prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
    prefix xml:<http://www.w3.org/XML/1998/namespace>
    prefix xsd:<http://www.w3.org/2001/XMLSchema#>
    prefix rdfs:<http://www.w3.org/2000/01/rdf-schema#>
    PREFIX onto: <http://www.ontotext.com/>
    PREFIX sio: <http://semanticscience.org/resource/>
    PREFIX local: <urn:local:>

    SELECT ?sec (str(?seclab) as ?label)  WHERE {
      accv:#{questionnaire_type} local:has-fields ?sec .
      ?sec rdfs:label ?seclab .
    }
GET_CATEGORY_SECTIONS
qs = SPARQL.parse(qs)
qs.execute(ONTOLOGY)
end

def get_section_questions_query(sectionid:) # sectionid  must be just teh ID
  qs = <<GET_SECTION_QUESTIONS
  prefix accv: <https://w3id.org/CBGP-App#>
  prefix owl: <http://www.w3.org/2002/07/owl#>
  prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
  prefix xml:<http://www.w3.org/XML/1998/namespace>
  prefix xsd:<http://www.w3.org/2001/XMLSchema#>
  prefix rdfs:<http://www.w3.org/2000/01/rdf-schema#>
  PREFIX onto: <http://www.ontotext.com/>
  PREFIX sio: <http://semanticscience.org/resource/>
  PREFIX local: <urn:local:>

  SELECT ?q (str(?qlab) as ?label) ?widget ?class ?method ?cardinality ?answers ?sequence  WHERE {
    ?q rdfs:subClassOf accv:#{sectionid} .
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
  prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
  prefix accv: <https://w3id.org/CBGP-App#>
  prefix xml:<http://www.w3.org/XML/1998/namespace>
  prefix xsd:<http://www.w3.org/2001/XMLSchema#>
  prefix rdfs:<http://www.w3.org/2000/01/rdf-schema#>
  PREFIX onto: <http://www.ontotext.com/>
  PREFIX sio: <http://semanticscience.org/resource/>
  PREFIX local: <urn:local:>

  SELECT DISTINCT ?aid ?label ?sequence WHERE {
      ?aid rdfs:subClassOf accv:#{ablockid} .
      ?aid rdfs:label ?label .
      ?aid local:answer-order ?sequence .
  } ORDER BY ?sequence
GET_ANSWER_BLOCK
a = SPARQL.parse(a)
a.execute(ONTOLOGY)
end

def get_label_for_questionnaire_type(id:)
  lab = SPARQL.parse("
    prefix accv: <https://w3id.org/CBGP-App#>
    prefix owl: <http://www.w3.org/2002/07/owl#>
    prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
    prefix xml:<http://www.w3.org/XML/1998/namespace>
    prefix xsd:<http://www.w3.org/2001/XMLSchema#>
    prefix rdfs:<http://www.w3.org/2000/01/rdf-schema#>
    PREFIX onto: <http://www.ontotext.com/>
    PREFIX sio: <http://semanticscience.org/resource/>

    select ?plabel ?label where {
    accv:#{id} rdfs:label ?label ;
                 rdfs:subClassOf ?parent .
          ?parent rdfs:label ?plabel

    }
          ")

  res = lab.execute(ONTOLOGY)
  [res.first[:plabel].to_s, res.first[:label].to_s]
end

def get_label_for_id(id:)
  lab = SPARQL.parse("
      prefix accv: <https://w3id.org/CBGP-App#>
    prefix owl: <http://www.w3.org/2002/07/owl#>
    prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
    prefix xml:<http://www.w3.org/XML/1998/namespace>
    prefix xsd:<http://www.w3.org/2001/XMLSchema#>
    prefix rdfs:<http://www.w3.org/2000/01/rdf-schema#>
    PREFIX onto: <http://www.ontotext.com/>
    PREFIX sio: <http://semanticscience.org/resource/>

    select ?label where {
      		accv:#{id} rdfs:label ?label .
    }
          ")

  res = lab.execute(ONTOLOGY)
  res.first[:label].to_s
end

# def get_labels_by_id(questionnaire_type:)
#   sl = <<~GET_SECTION_LABELS
#       prefix accv: <https://w3id.org/CBGP-App#>
#     prefix owl: <http://www.w3.org/2002/07/owl#>
#     prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
#     prefix xml:<http://www.w3.org/XML/1998/namespace>
#     prefix xsd:<http://www.w3.org/2001/XMLSchema#>
#     prefix rdfs:<http://www.w3.org/2000/01/rdf-schema#>
#     PREFIX onto: <http://www.ontotext.com/>
#     PREFIX sio: <http://semanticscience.org/resource/>

#     select ?ppl ?acl where {
#           ?q rdfs:subClassOf sio:SIO_000171 .
#       		?q rdfs:label "Questionnaire"@en .
#       		?q rdfs:label ?ql .
#       		?pp rdfs:subClassOf ?q .
#       		?pp rdfs:label ?ppl .
#       		?ac rdfs:subClassOf ?pp .
#       		?ac rdfs:label ?acl .
#       FILTER(CONTAINS(str(?ac), "#{questionnaire_type}"))
#     }

#   GET_SECTION_LABELS
#   sl = SPARQL.parse(sl)
#   sl.execute(ONTOLOGY)
# end

# def get_sections_labels(lang: 'EN', patprof: 'Patient', adultchild: 'Child')
#   sl = <<~GET_SECTION_LABELS
#       prefix accv: <https://w3id.org/CBGP-App#>
#     prefix owl: <http://www.w3.org/2002/07/owl#>
#     prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
#     prefix xml:<http://www.w3.org/XML/1998/namespace>
#     prefix xsd:<http://www.w3.org/2001/XMLSchema#>
#     prefix rdfs:<http://www.w3.org/2000/01/rdf-schema#>
#     PREFIX onto: <http://www.ontotext.com/>
#     PREFIX sio: <http://semanticscience.org/resource/>

#     select ?q (str(?ql) as ?qlabel) ?pp (str(?ppl) as ?pplabel) ?ac (str(?acl) as ?aclabel) from onto:explicit where {
#     #{'    '}
#           ?q rdfs:subClassOf sio:SIO_000171 .
#       		?q rdfs:label "Questionnaire"@en .
#       		?q rdfs:label ?ql .
#       		?pp rdfs:subClassOf ?q .
#       		?pp rdfs:label "#{patprof}"@en .
#       		?pp rdfs:label ?ppl .
#       		?ac rdfs:subClassOf ?pp .
#       		?ac rdfs:label "#{adultchild}"@en .
#       		?ac rdfs:label ?acl .
#     }

#   GET_SECTION_LABELS
#   sl.execute(ONTOLOGY)
# end



# def get_form_fields_query(form: 'publication', lang: 'EN')
#   fields = SPARQL.parse(
#     "
#   PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
#   PREFIX sio: <http://semanticscience.org/resource/>
#   PREFIX local: <urn:local:>

#   SELECT ?field ?label ?widget ?cardinality WHERE
#     {
#     <https://w3id.org/CBGP-App#add-#{form}> local:has-fields ?fields .
#     ?field rdfs:subClassOf ?fields .
#     ?field rdfs:label ?label .
#     ?field local:widget-cardinality ?cardinality .
#     ?field local:widget-types ?widget .
#     ?field local:question-order ?order 

#     } order by ?order"
#   )
#   fields.execute(ONTOLOGY)
# end