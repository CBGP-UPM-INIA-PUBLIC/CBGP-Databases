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

## How values are typed

Every field value is an RDF *literal* on the attribute node (the
`sio:SIO_000300` triple above). Most are plain text — including currency
amounts, which are kept in their canonical decimal form (`15000.50`) — but
**dates are real dates**: a literal of datatype `xsd:date`.

```turtle
<attribute-node>
    rdf:type cbgp:project_start_date ;
    sio:SIO_000300 "2026-01-31"^^xsd:date .
```

This is not cosmetic. A SPARQL comparison between a plain-text literal and a
date does not raise an error on this triple store — it quietly gives the
wrong rows. (When this was found, "projects started on or before today"
returned nothing and "starting after today" returned everything, for dates
stored as text.) Typed dates compare correctly, and so does every date-range
search.

How a field comes to be a date, and what gets checked:

- A field is treated as a date if its **widget** is a date picker, *whatever
  object-class the ontology declares for it*. (Several date-picker fields were
  once declared as strings; the application no longer depends on the two being
  kept in step. Declaring `local:object-class Date` for them, as the ontology
  now does, just says what is already meant.)
- The value is parsed and normalised to `YYYY-MM-DD` when a record is saved,
  and a value that is not a real calendar date is **refused**, not stored as
  text.
- Reading a date back, and every display and export, uses the same
  `YYYY-MM-DD` text as before, so nothing downstream changes.

**Writing queries.** In SPARQL, compare a stored date with the **function
form** of the bound, not a typed literal:

```sparql
PREFIX cbgp: <https://w3id.org/CBGP-App#>
PREFIX sio: <http://semanticscience.org/resource/>
PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>

SELECT ?record WHERE {
  GRAPH ?record {
    ?ds sio:SIO_000008 ?a .
    ?a a cbgp:project_start_date ; sio:SIO_000300 ?start .
    FILTER (?start <= xsd:date("2026-10-06"))    # not  "2026-10-06"^^xsd:date
  }
}
```

The `xsd:date("…")` form is the one Virtuoso's own [date-range
documentation](http://docs.openlinksw.com/virtuoso/virtuosotipsandtricksmanagedaterangequery/)
uses. On the full set of member records here, the `"…"^^xsd:date` literal form
silently dropped rows (12 of 919 for "on or before today") while the function
form returned all of them; the cause was not established, so treat this as an
observed behaviour of this store rather than a documented rule.

Records written before this change hold their dates as text. They are
converted with a one-off script — see [Backup &
Migration](backup_and_migration.md#retyping-dates-stored-as-text).

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

### Core and user-facing forms, and sharing a dbname

A form declares which **category** it belongs to with `local:form-category`:
`Core` for the forms administrators add and edit records with (the ones listed
under Add Data and Query Data), `UserFacing` for the smaller forms the User
side offers. Several forms of either category can share one `local:dbname` —
the four Core project forms and the user-facing project form all store under
`project` — and a record's `dcterms:type` says which one wrote it.

Two consequences, both generic (nothing here is about projects):

- A **cross-reference** to a shared dbname resolves to the *union* of every
  form's fields, as described in the worked example below, so a reference can
  point at a record whichever form created it. A **search** of the shared
  dbname is the opposite: it can only meaningfully ask a question that *every*
  record can answer, so its form and result columns are the fields that all the
  **Core** forms have in common ([Search &
  Queries](admin/search_and_queries.md#searching-every-kind-of-project-at-once)).
  `UserFacing` forms are left out of that intersection, otherwise a cut-down
  form would shrink it to almost nothing.
- A record still stamped with a `UserFacing` form can be **curated**: opened
  under a Core form of the same dbname and saved, which rewrites the stamp and
  nothing else about its identity. See [Data
  Entry](admin/data_entry.md#curating-a-project-submitted-by-a-member).

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
                                             local:has-conditional-requirements
                                                                    (optional, per-form fields
                                                                      required only for some
                                                                      answers of another field)
                                             local:has-related-records
                                                                    (optional, panels listing
                                                                      records of another form
                                                                      that point back at this one)
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

(interface-text)=
## Interface text lives in the ontology

Field labels and answers come from the ontology, and so does the *other*
text a person reads on a page: the hints inside boxes, the captions of small
buttons, the notes beside a field, and the names of the entries in the Query
Data list. Each piece of text is a class that is a subclass of
`cbgp:ui-text`, and its `rdfs:label` in each language is what the person
sees — so the people who maintain the ontology can reword or translate it
without a programmer.

```turtle
cbgp:ui_search_show_all
    rdfs:subClassOf cbgp:ui-text ;
    rdfs:label "Show all records"@en , "Mostrar todos los registros"@es .
```

- **The name is the key.** The code asks for a text by a dotted key, such as
  `search.show_all`, and the class is that key with the dots turned into
  underscores and `ui_` in front: `ui_search_show_all`.
- **Placeholders.** A `%{name}` in a text is filled in by the code, for
  example `"Showing all records (%{count})."`. Every language of a text must
  use exactly the same placeholders.
- **Fallbacks.** A text missing in the current language shows its English
  version; one missing entirely shows its key, which makes the gap visible on
  the page rather than raising an error.
- **Characters.** Because these texts are printed into HTML attributes and
  scripts, they may not contain a double quote, a back-tick, `<`, `>`, a
  backslash or `${`.
- **Names of search entries.** A group of forms stored together (see above)
  is named by `ui_dbname_<dbname>` — `ui_dbname_project` is "Projects (all
  types)" — and, if there is none, by the generic `ui_dbname_all_types`,
  "`%{name}` (all types)".

`check_ontology.rb` rejects a text whose languages disagree on placeholders or
that contains a forbidden character, and the application's own tests fail if
the code asks for a key the ontology doesn't have. A text that is still
hard-coded in English in the application (some older parts) is not yet one of
these; moving it into the ontology is only a matter of adding the class and
asking for the key.

## Worked example: is a field required, defaulted, or calculated on this form?

The per-form mechanisms mentioned above (`local:has-defaults`,
`local:has-formulas`, `local:requires-field`, and the conditional
variant of the last one, covered at the end) are all declared on the
**Form**, not on the Question — because the same shared Question can
behave differently depending on which Form is using it. Each one below
uses a different real field from the Personnel and European Commission
Project forms, on purpose - the field that actually demonstrates that mechanism, rather
than pretending all of them apply to one field they don't.

### `local:requires-field` — direct

This one links the Form straight to the Question, no node in between.
Personnel Project requires its Total funding:

```turtle
cbgp:personnel_project local:requires-field cbgp:personnel_project_total_funding .
```

`local:has-defaults` and `local:has-formulas` are *not* this simple —
each needs **two** pieces of information (which field, and what
value/formula), not one, so each needs somewhere to hold both. Both go
through an **intermediate node** instead of a direct link - this is the
part that isn't obvious just from skimming a triple like
`local:requires-field cbgp:personnel_project_total_funding`, because there is no
equivalent single triple for a default or a formula.

### `local:has-defaults` — via an intermediate node

Every Core project form gives the shared *Funding status* field the same
starting value, `Proposed` — but each does it through its **own** node, which
is what would let one form start from a different value without touching the
others. Personnel Project's:

```turtle
cbgp:personnel_project
    local:has-defaults cbgp:personnel_project_status_default .

cbgp:personnel_project_status_default
    rdfs:subClassOf         cbgp:pre-populated-answer ;
    local:default-for-field cbgp:project_status ;
    local:default-value     "Proposed" .
```

The European Commission Research Project form points at *its own* node,
`cbgp:european_research_project_status_default`, for the exact same
`local:default-for-field`.

### `local:has-formulas` — the same shape, one field computed from another

On the European Commission Research Project form, *Total overheads* is
calculated *from* *Total funding* (not the other way around — Total funding
is the input, Total overheads is what gets computed):

```turtle
cbgp:european_research_project
    local:has-formulas cbgp:european_research_project_overheads_formula .

cbgp:european_research_project_overheads_formula
    rdfs:subClassOf          cbgp:formula-definition ;
    local:formula-for-field  cbgp:european_research_project_total_overheads ;
    local:formula-expression "european_private_research_project_total_funding * 0.25" .
```

In both cases the Form never points at the Question directly - it points
at an in-between node (an ordinary class, named after the form and the field
by convention, but the name itself carries no meaning to the code), and *that* node is what names the actual field via
`local:default-for-field`/`local:formula-for-field`. Querying "what does
this form do with this field" always means one hop through the node,
never a direct Form-to-Question triple:

```sparql
PREFIX cbgp: <https://w3id.org/CBGP-App#>
PREFIX local: <urn:local:>

# Is Total funding required on the Personnel form?
ASK { cbgp:personnel_project local:requires-field cbgp:personnel_project_total_funding }

# What does the Personnel form default Funding status to?
# (two hops: Form -> default node -> the field the node is actually for)
SELECT ?value WHERE {
  cbgp:personnel_project local:has-defaults ?d .
  ?d local:default-for-field cbgp:project_status ;
     local:default-value     ?value .
}

# Does the European form calculate Total overheads automatically?
# (same two-hop shape: Form -> formula node -> the field it's actually for)
SELECT ?formula WHERE {
  cbgp:european_research_project local:has-formulas ?f .
  ?f local:formula-for-field cbgp:european_research_project_total_overheads ;
     local:formula-expression ?formula .
}
```

### Conditional requirements

`local:requires-field` is unconditional. A field that is required only
*sometimes* needs more pieces of information — which field, which other
field decides, and which answers make it required — so, like defaults and
formulas, it goes through an intermediate node. The start date of a
European Commission Research Project is required once the project is
Awarded:

```turtle
cbgp:european_research_project
    local:has-conditional-requirements cbgp:european_project_start_date_when_awarded .

cbgp:european_project_start_date_when_awarded
    rdfs:subClassOf  cbgp:conditional-requirement ;
    local:conditional-requirement-field        cbgp:project_start_date ;   # becomes required...
    local:conditional-requirement-when-field   cbgp:project_status ;       # ...depending on this field
    local:conditional-requirement-when-answer  cbgp:Awarded .              # ...having this answer
```

`local:conditional-requirement-when-answer` can be repeated, meaning "any of
these answers". The answers are the stored answer classes (`Awarded`, not its
translated label), so a rule works the same in every language. One node holds
**one** field, so two fields that become required together (a start and an end
date) get one node each. A field with a conditional rule should *not* also
carry an unconditional `local:requires-field` on the same form, or it is
simply always required.

```sparql
PREFIX cbgp: <https://w3id.org/CBGP-App#>
PREFIX local: <urn:local:>

# When is the start date required on the European form?
SELECT ?when_field ?answer WHERE {
  cbgp:european_research_project local:has-conditional-requirements ?r .
  ?r local:conditional-requirement-field       cbgp:project_start_date ;
     local:conditional-requirement-when-field  ?when_field ;
     local:conditional-requirement-when-answer ?answer .
}
```

The rule is enforced on the server when a record is saved (the error names
the condition) and shown as a small note beside the field. If the deciding
field has some other answer, or none, the field is optional. A rule that
points at a class that doesn't exist, or is missing a part, is reported by
`check_ontology.rb`; without that check it would just never apply.

Querying the *content* of a record never needs to know any of this — a
field's value is stored and read the same reified way regardless of
whether that form happened to require it, default it, or calculate it.
These mechanisms only affect what happens *before* a value is
written (validation, pre-population, computation) — see [Data
Entry](admin/data_entry.md) for what each looks like from the form-filling
side.

## Worked example: one record that points at two others

A person funded 50/30/20 by three projects is the case where a flat field
can't do the job: "project X, 50%" is a *pair*, and a list of projects
next to a separate list of percentages can't be reliably lined up. So the
pair gets its own record — a **Funding Commitment** — whose fields are two
[cross-references](admin/cross_references.md) plus the numbers that belong
to the pairing:

```turtle
cbgp:funding_commitment
    rdfs:subClassOf  cbgp:forms ;
    local:dbname     "commitment" ;
    local:has-fields cbgp:new-commitment-questions ;
    local:requires-field cbgp:commitment_member, cbgp:commitment_project,
                         cbgp:commitment_percentage, cbgp:commitment_start_date .

cbgp:commitment_member
    local:references       cbgp:member ;
    local:references-via   cbgp:member_dni_nie_pas ;   # what is stored
    local:references-label cbgp:member_surnames .      # what is searched/shown

cbgp:commitment_project
    local:references       cbgp:project ;               # the shared dbname, see below
    local:references-via   cbgp:project_internal_code ;
    local:references-label cbgp:project_title .
```

`cbgp:project` there is not a form: since the project forms were split
(European, National/Regional, Private, Personnel) no ontology class is
literally called `project`; it is only the `local:dbname` those forms
share. A cross-reference to a name that is a shared dbname rather than a
form resolves to the **union of the fields of every form using it**, which
is what lets a commitment point at a project whichever form created it.

The list shown under a member's or project's edit form is declared the same
way as the other per-form mechanisms — an intermediate node that holds the
details, nothing in the code that knows about commitments:

```turtle
cbgp:member
    local:has-related-records cbgp:member_commitments_panel .

cbgp:member_commitments_panel
    rdfs:subClassOf  cbgp:related-records-definition ;
    local:related-form  cbgp:funding_commitment ;
    local:related-via   cbgp:commitment_member ;        # the field that points back
    local:related-column cbgp:commitment_project, cbgp:commitment_percentage,
                         cbgp:commitment_start_date, cbgp:commitment_end_date ;
    # optional: add up one field over the rows that are active today
    local:related-sum-field          cbgp:commitment_percentage ;
    local:related-active-from-field  cbgp:commitment_start_date ;
    local:related-active-to-field    cbgp:commitment_end_date ;
    local:related-expected-total     100 ;
    local:related-tolerance          0.05 .             # percentages are stored to 2 decimals
```

The project-side panel is the same shape with `related-via
cbgp:commitment_project` and no sum. The warning is computed every time
the page is shown and never stored.

To find the commitments themselves in the data, use the same two-layer
shape as the query above — for instance, every commitment for one person
(the stored member value is their DNI/NIE/PAS):

```sparql
PREFIX cbgp: <https://w3id.org/CBGP-App#>
PREFIX sio: <http://semanticscience.org/resource/>
PREFIX dcterms: <http://purl.org/dc/terms/>

SELECT ?project ?percentage ?from ?to WHERE {
  ?record dcterms:type cbgp:funding_commitment .
  GRAPH ?record {
    ?ds sio:SIO_000008 ?m, ?p, ?pc, ?f .
    ?m  a cbgp:commitment_member     ; sio:SIO_000300 "12345678Z" .
    ?p  a cbgp:commitment_project    ; sio:SIO_000300 ?project .
    ?pc a cbgp:commitment_percentage ; sio:SIO_000300 ?percentage .
    ?f  a cbgp:commitment_start_date ; sio:SIO_000300 ?from .
    OPTIONAL { ?ds sio:SIO_000008 ?e .
               ?e a cbgp:commitment_end_date ; sio:SIO_000300 ?to }
  }
}
```
