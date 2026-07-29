# Data Model

This page is for anyone who needs to write a raw SPARQL query against the
triple store directly — a report, a one-off analysis, an export this
system doesn't already provide — rather than going through the app's own
search screens. It explains the two things every record actually looks
like on disk, and how both connect back to the ontology.

If you only ever use the web app, you don't need this page — see [Data
Entry](admin/data_entry.md) and [Search & Queries](admin/search_and_queries.md)
instead. This is a level below that.

## Two layers, one record

Every record lives in its own **named graph** — a self-contained bucket
of triples, one per record, identified by its own URI (e.g.
`.../project/context/<uuid>`). But a record is described by triples in
**two different places**, not one:

- **Graph metadata** — a handful of triples *about* the record as a
  whole (when it was created, when it last changed, which form produced
  it). These live in the triple store's **default graph**, with the
  record's own graph URI as their *subject*. They are deliberately kept
  out of the named graph itself, so a query can always find them without
  first knowing anything about what fields the record has.
- **Graph content** — the record's actual field values, *inside* the
  named graph. Every field is stored as a small node of its own (a
  *reified attribute*), not as one direct triple, so that this exact
  shape can be snapshotted and reconstructed later — see [Time
  Travel](time_travel.md).

```text
Graph URI:  .../project/context/<uuid>

┌─ GRAPH METADATA ───────────────────────────────────┐
│  (in the DEFAULT graph, subject = the graph URI)    │
│                                                      │
│  <graph URI>                                        │
│    dcterms:created   "2026-01-10T09:00:00Z" ;       │
│    dcterms:modified  "2026-07-29T11:20:00Z" ;       │
│    dcterms:type      cbgp:personnel_project .       │
└──────────────────────────────────────────────────────┘

┌─ GRAPH CONTENT ─────────────────────────────────────┐
│  (INSIDE the named graph itself)                    │
│                                                      │
│  dataset:<uuid>                                     │
│    rdf:type sio:SIO_000089 ;                        │
│    sio:SIO_000008 <attribute-node> .                │
│                                                      │
│  <attribute-node>                                   │
│    rdf:type cbgp:project_annual_income ;            │
│    sio:SIO_000300 "45000.00" .                      │
└──────────────────────────────────────────────────────┘
```

`dcterms:created`/`dcterms:modified`/`dcterms:type` are real,
standard [Dublin Core](https://www.dublincore.org/specifications/dublin-core/dcmi-terms/)
terms — not something invented for this project. `sio:SIO_000089`,
`sio:SIO_000008`, and `sio:SIO_000300` come from the
[Semanticscience Integrated Ontology (SIO)](https://github.com/MaastrichtU-IDS/semanticscience),
a general-purpose ontology for exactly this "thing has an attribute which
has a value" shape.

## `dcterms:type`: which form wrote this record

Several record types share one underlying table (Research Project and
Personnel Project both live under the `project` dbname, for example), so
the dbname alone can't tell you which *form* actually created a given
record. `dcterms:type` answers that directly, and — this is the part
worth remembering when writing a query — **its value is the form's own
ontology class URI**, not a plain string:

```sparql
PREFIX cbgp: <https://w3id.org/CBGP-App#>
PREFIX dcterms: <http://purl.org/dc/terms/>

# Every record created through the Personnel Project form
SELECT ?record WHERE {
  ?record dcterms:type cbgp:personnel_project .
}
```

Because the object is a real class URI, its display label comes for free
from the ontology itself — every Form already carries a bilingual
`rdfs:label`:

```sparql
PREFIX cbgp: <https://w3id.org/CBGP-App#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

SELECT ?label WHERE {
  cbgp:personnel_project rdfs:label ?label .
  FILTER(lang(?label) = "en")   # or "es"
}
# -> "Personnel Project"
```

This stamp is written automatically, for every record on every form, at
save time — there is nothing to configure in the ontology for a new form
to get one. See [Calculated Fields](admin/data_entry.md#calculated-fields)
for the other place this session's work touched the data model.

## Crossing both layers in one query

A form-scoped question, like "what's the total Annual income across every
Personnel Project record," needs both layers together: `dcterms:type` (in
the default graph) to pick out the right records, then each one's own
named graph to read a field value out of it.

```sparql
PREFIX cbgp: <https://w3id.org/CBGP-App#>
PREFIX sio: <http://semanticscience.org/resource/>
PREFIX dcterms: <http://purl.org/dc/terms/>

SELECT ?record ?income WHERE {
  ?record dcterms:type cbgp:personnel_project .
  GRAPH ?record {
    ?ds sio:SIO_000008 ?attr .
    ?attr a cbgp:project_annual_income ;
          sio:SIO_000300 ?income .
  }
}
```

## How this connects to the ontology

Every predicate used above (`cbgp:personnel_project`, `cbgp:project_annual_income`)
is a class declared in the ontology, not an arbitrary string — which is
what makes both diagrams below the same picture, seen from two different
angles.

```text
DATA (what gets written)                 ONTOLOGY (what defines it)
─────────────────────────                ───────────────────────────

dcterms:type cbgp:personnel_project  ──►  cbgp:personnel_project  (a Form)
                                             local:dbname           "project"
                                             local:has-fields   ──► a Section
                                             local:has-defaults     (optional, per-form
                                                                      default values)
                                             local:has-formulas     (optional, per-form
                                                                      calculated fields)
                                             local:requires-field   (optional, per-form
                                                                      required fields)
                                                   │
                                                   │ has-fields
                                                   ▼
<attribute-node>                          new-personnel-project-questions  (a Section)
  rdf:type cbgp:project_annual_income ─►         │
  sio:SIO_000300 "45000.00"                       │ subClassOf
                                                   ▼
                                           cbgp:project_annual_income  (a Question)
                                             local:method        "annual_income"
                                             local:object-class  "Currency"
                                             rdfs:label          "Annual income" /
                                                                   "Ingreso anual"
```

A Question's `local:answer-block`, when it has one, points at a set of
Answer classes the same way — see [Philosophy & Design](philosophy.md#how-it-actually-works-without-the-code)
for the full ontology-to-form-rendering path this same class structure
also drives.

## Worked example: is a field required, defaulted, or calculated on this form?

The three per-form mechanisms mentioned above (`local:has-defaults`,
`local:has-formulas`, `local:requires-field`) are all declared on the
**Form**, not on the Question — because the same shared Question can
behave differently depending on which Form is using it. To find out how
`cbgp:project_annual_income` behaves specifically on the Personnel
Project form:

### `local:requires-field` — direct

This one links the Form straight to the Question, no node in between:

```turtle
cbgp:personnel_project local:requires-field cbgp:project_annual_income .
```

`local:has-defaults` is *not* this simple — a default needs two pieces of
information (which field, and what value), so it needs somewhere to hold
both. `local:has-formulas` needs exactly the same two things (which
field, and what formula), for exactly the same reason. Both go through an
**intermediate node** instead of a direct link — this is the part that
isn't obvious just from skimming a triple like `local:requires-field
cbgp:project_annual_income`, because there is no equivalent single triple
for a formula. There are two:

```turtle
cbgp:personnel_project
    local:has-formulas cbgp:project_cbgp_overheads_personnel_formula .

cbgp:project_cbgp_overheads_personnel_formula
    rdfs:subClassOf     cbgp:formula-definition ;
    local:formula-for-field  cbgp:project_annual_income ;
    local:formula-expression "project_annual_income * 0.08" .
```

The Form never points at the Question directly — it points at this
in-between node (an ordinary class, `<form>_<field>_<form-again>_formula`
by convention, but the name itself carries no meaning to the code), and
*that* node is what names the actual field via `local:formula-for-field`.
The same shape, one level simpler (only one piece of information instead
of two), is what `local:has-defaults` uses via `cbgp:pre-populated-answer`
nodes. Querying which field a formula node is *for* always means one hop
through the node, never a direct Form-to-Question triple:

```sparql
PREFIX cbgp: <https://w3id.org/CBGP-App#>
PREFIX local: <urn:local:>

# Is it required on this form?
ASK { cbgp:personnel_project local:requires-field cbgp:project_annual_income }

# Does this form calculate it automatically? (two hops: Form -> formula
# node -> the field the formula node is actually for)
SELECT ?formula WHERE {
  cbgp:personnel_project local:has-formulas ?f .
  ?f local:formula-for-field cbgp:project_annual_income ;
     local:formula-expression ?formula .
}
```

Querying the *content* of a record never needs to know any of this — a
field's value is stored and read the same reified way regardless of
whether that form happened to require it, default it, or calculate it.
These three mechanisms only affect what happens *before* a value is
written (validation, pre-population, computation) — see [Data
Entry](admin/data_entry.md) for what each looks like from the form-filling
side.
