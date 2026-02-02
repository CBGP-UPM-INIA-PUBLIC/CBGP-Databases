from rdflib import Graph, Namespace, URIRef
from collections import defaultdict

def get_forms():
    owl_url = "/home/wilkinsonlab2/jinja/ontology.owl"  
    g = Graph()
    
    try:
        g.parse(owl_url, format="xml")
        print(f"Número de triples en el grafo: {len(g)}")  # Verificar si se cargaron datos
    except Exception as e:
        print(f"Error al cargar el OWL: {e}")
        return None
    
    CBGP = Namespace("https://w3id.org/CBGP-App/cbgp-application-ontology.owl#")

    query = """
    PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
    PREFIX cbgp: <https://w3id.org/CBGP-App/cbgp-application-ontology.owl#>
    PREFIX cbgp-local: <urn:cbgp-local:>

    SELECT ?x ?xlabel ?qlabel ?q ?question ?questionlabel ?wt ?wtlabel ?order ?radiopt ?radioptlabel ?radiorder
    WHERE {
        ?x rdfs:label ?xlabel .
        ?x cbgp-local:has-fields ?q .
        ?q rdfs:label ?qlabel .
        ?question rdfs:subClassOf ?q .
        OPTIONAL { ?question cbgp-local:question-order ?order . }
        ?question rdfs:label ?questionlabel .
        ?question cbgp-local:widget-types ?wt .
        ?wt rdfs:label ?wtlabel .
        OPTIONAL {
            ?radiopt rdfs:subClassOf ?question .
            ?radiopt rdfs:label ?radioptlabel .
            ?radiopt cbgp-local:answer-order ?radiorder .
            FILTER (LANG(?radioptlabel)="en")

        }
    }
    ORDER BY ?order ?radiorder
    """

    try:
        results = g.query(query)

        # Convert query results into a structured dictionary
        form_data = defaultdict(lambda: {
            "uri": None,
            "xlabel": None,
            "qlabel": None,
            "q": None,
            "question": None,
            "questionlabel": None,
            "wtlabel": None,
            "radio_options": []
        })

        for row in results:
            key = str(row.question)  # Group by question

            # Fill basic question details
            form_data[key]["uri"] = str(row.x)
            form_data[key]["xlabel"] = str(row.xlabel)
            form_data[key]["qlabel"] = str(row.qlabel)
            form_data[key]["q"] = str(row.q)
            form_data[key]["question"] = str(row.question)
            form_data[key]["questionlabel"] = str(row.questionlabel)
            form_data[key]["wtlabel"] = str(row.wtlabel)

            # Add radio button options if applicable
            if row.radiopt and row.radioptlabel:
                form_data[key]["radio_options"].append({
                    "id": str(row.radiopt),
                    "label": str(row.radioptlabel)
                })

        return list(form_data.values())

    except Exception as e:
        print(f"Error en la consulta SPARQL: {e}")
        return None

# Ejecutar la función y ver resultados
if __name__ == "__main__":
    data = get_forms()
    print(data)

