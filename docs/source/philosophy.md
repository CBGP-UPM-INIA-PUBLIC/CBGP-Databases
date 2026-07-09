# Philosophy & Design

## The one-sentence version

Every field, every dropdown, every form, every language label in this
application is read out of a single OWL ontology file at the moment it's
needed — nothing about *what* the institute tracks, or *how* a form for it
looks, is written into the program's code. The code only knows how to ask
the ontology "what fields does a Project have, and how should I draw them?"
It never hardcodes the answer.

That single design choice is what lets the people who actually understand
the institute's data — an administrator, not a programmer — add a field,
change a dropdown's options, or reword a label, just by editing the
ontology, with no software release involved.

## Why this exists

The institute's real data is genuinely complicated and keeps changing
shape: people are paid from more than one project at once, roles and
affiliations change over a career, funding rules get added, a new type of
record turns out to be needed. Traditional software handles that kind of
change with a programmer: someone edits the code, tests it, deploys it.
That's a real bottleneck — every small change waits on a developer's time,
and every developer who ever touches the system has to be trusted not to
quietly break something else.

This system was built to remove that bottleneck entirely for the *shape* of
the data — which fields exist, what they're called (in English or
Spanish), what kind of answers they accept, whether a field can have one
value or several, which fields link to which other records — while keeping
programmer involvement for genuinely new *behavior* (a new kind of report,
a new integration with an external database). Changing what a Project
record looks like should never require the second kind of change. In this
system, it doesn't.

## How it actually works, without the code

Behind the scenes, the ontology is written in [OWL](https://www.w3.org/OWL/)
(the standard language for describing things and their relationships on
the Semantic Web) and hosted as a normal file the application reads over
the network. Alongside the *real* meaning of a class — "a Project has a
title, a start date, a funding amount" — the ontology also carries a small
set of extra instructions specifically for this application: what kind of
input box to draw for a field (a plain text box, a date picker, a
dropdown, a currency field, a searchable lookup into another table...),
what order fields appear in, which fields are required, which dropdown
options exist and what they're labeled in each language, and which fields
are actually references to a record in a *different* table (e.g. a
project's "Responsible PI" field is really a lookup into the Personnel
table).

When an administrator opens a form, the application asks the ontology "what
does a Project look like right now?", gets back that list of fields and
instructions, and builds the page on the spot. Add a field to the ontology
and it appears on the form the next time someone loads it — no waiting for
a new version of the software.

## Strict separation of code from structure

It's worth being precise about what this means, because it's easy to
undersell: the application's code does not contain the word "Project," or
"Member," or the name of a single field, anywhere. If you deleted the
entire Projects section from the ontology tomorrow and replaced it with
something describing, say, laboratory equipment instead, the same code
would start rendering equipment-tracking forms without a single line
changing. The code is a generic engine for "read a class definition from
the ontology, render it, validate submissions against it, store and
retrieve records that match it." The ontology is the only place that says
what the institute is actually tracking.

This is also why the system can safely be handed to people who don't
write code: the worst a mistake in the ontology can do is produce a
confusing or broken *form* — it can't introduce a security hole or crash
the server the way a code change could, because the code paths themselves
never change.

## Multilingual by the same mechanism, not as an afterthought

Every label, every dropdown option, and every help tooltip in the ontology
is written once per language (English and Spanish today) as ordinary data
on the same class — not as a separate translation file that has to be kept
in sync by hand. The running application shows a small language toggle at
the top of every page; switching it re-reads the *same* ontology, just
asking for the Spanish label instead of the English one. Adding a third
language later is a matter of adding a third label to each class in the
ontology, not building a new feature.

## Is this novel? Where it sits relative to other approaches

Generating a database and a CRUD (create/read/update/delete) interface
from a schema is not a new idea — it's the whole premise behind Ruby on
Rails' scaffolding and Django's admin site, and behind newer low-code
platforms like Airtable or NocoDB. It's worth being explicit about why
this project is a genuinely different thing, not just another entry in
that list, and about the real prior art that's closest to it — because the
honest answer is "closer than you'd think, but not the same as anything
in wide use":

- **Rails/Django scaffolding** generates code and database tables *from* a
  schema at development time; after that, the schema lives in migration
  files and model code, editable only by a programmer. There's no ontology
  involved, no shared vocabulary, and nothing semantic about the result —
  it's a productivity shortcut for programmers, not a tool handed to
  non-programmers.
- **Low-code platforms** (Airtable, NocoDB, and similar) do let
  non-programmers add fields and change forms through a UI, which is the
  closest surface-level resemblance. But the schema they use is internal
  and proprietary to that platform — it isn't a portable, standards-based
  description of the domain that means anything outside that one tool.
- **[CEDAR Workbench](https://arxiv.org/abs/1905.06480)** (Stanford/Center
  for Expanded Data Annotation and Retrieval) is much closer in spirit: it
  auto-generates metadata-entry forms and is explicitly "ontology-assisted"
  — form fields can pull their controlled-vocabulary options live from
  BioPortal ontologies, and the output is RDF/JSON-LD. The difference is
  structural: CEDAR keeps a separate *template* model (built with its own
  Template Designer) that merely *references* ontology terms for
  vocabulary lookups. The template, not the ontology, is what defines the
  form. Here, there is no separate template layer at all — the domain
  ontology *is* the template.
- **[VIVO](https://www.w3.org/community/vivo/)**, the ontology-based
  research-information system used by many universities, is probably the
  closest full production system to this one: it's built around an OWL
  ontology (VIVO-ISF) and uses additional "application configuration" and
  "display model" ontologies specifically to drive its UI. That's
  extremely close to this project's approach — with the difference that
  VIVO keeps the display/configuration ontology as a separate auxiliary
  ontology alongside the domain ontology, whereas here the UI directives
  (widget type, field order, answer lists, cross-references) are
  annotation properties directly on the *same* domain classes. One
  ontology file, not two linked ones.
- **Wikibase** (the software behind Wikidata) drives its entity-editing
  forms from property *datatypes* — a property declared as "quantity,"
  "item reference," or "external identifier" determines which input widget
  Wikidata shows editors, at a scale of billions of statements. It's a
  real, live demonstration that "let the schema pick the widget" works at
  serious scale — but Wikibase's property system is deliberately
  lightweight (a flat list of typed properties) rather than a full OWL
  class hierarchy with per-class field lists, ordering, and multilingual
  answer trees.
- **[SHACL](https://www.w3.org/TR/shacl/) combined with the
  [DASH vocabulary](https://datashapes.org/forms.html)** is the closest
  *standards-based* prior art found for this pattern specifically. SHACL
  is the W3C standard for describing constraints on RDF data ("this class
  must have exactly one title, of type string"); the DASH vocabulary
  extends it with UI-specific annotations — `dash:editor`,
  `dash:singleLine`, `dash:defaultViewForRole` — so a *shape* can carry
  both validation rules and rendering instructions at once, and tools like
  [Schímatos](https://github.com/schimatos/schimatos.org) and
  [shacl-form](https://github.com/ULB-Darmstadt/shacl-form) generate real
  editing forms straight from SHACL shapes annotated this way. This is
  conceptually the same move this project makes — annotate the schema
  itself with UI directives rather than maintaining a second artifact —
  arrived at independently, using plain OWL classes and a small
  purpose-built `local:` vocabulary rather than SHACL/DASH.

Put together: the idea of using a schema to drive a form is old, and the
idea of layering UI hints onto a semantic schema has real, if
narrowly-adopted, prior art (VIVO, SHACL/DASH). What appears genuinely
uncommon is combining *all* of it — a full OWL class hierarchy as the
single source of truth for the domain model, per-class widget/ordering/
cross-reference/multilingual-label directives folded directly into that
same ontology rather than a second linked one, and (as of the SCD history
feature) the same mechanism extended to reconstructing what a record used
to look like at any point in the past — in one production administrative
tool built for non-programmer curators, rather than a research prototype
or a metadata-authoring sandbox. If there's prior art that does exactly
this combination, it isn't widely known — which is as much an invitation
to keep looking as it is a claim of uniqueness.

### Why not adopt SHACL/DASH directly?

Given how close SHACL plus the DASH vocabulary comes to this project's own
approach, it's a fair question why this system uses a small purpose-built
`local:` vocabulary instead of those existing W3C/community standards
outright. Two honest reasons, one about what SHACL is *for* and one about
what this system needed on top of it:

- **SHACL solves a different primary problem than this system needed
  solved.** SHACL's core purpose is *validating* that RDF data conforms to
  a shape — "this class must have exactly one title, of type string." DASH
  layers UI hints on top of that validation vocabulary as an extension,
  not as its main design goal. This system's central requirement runs the
  other way: render a working, ordered, multilingual *form* first, with
  validation as one part of that, not the starting point. Plain OWL
  classes with a small custom annotation vocabulary were simply the more
  direct route to "read a class, get back a form" — and OWL was already
  the natural choice for the parts of the ontology that carry real domain
  meaning (what a Project *is*), so reusing it for the UI-facing
  annotations too meant one modeling language throughout, not two.
- **The data storage pattern underneath predates, and doesn't match, how
  SHACL-validated data is normally shaped.** Every value in this system is
  stored as a *reified* attribute — a small node of its own,
  `?attribute rdf:type cbgp:project_title ; sio:SIO_000300 "..."`, rather
  than a direct `?project cbgp:title "..."` triple — specifically so that
  the [history/"time machine" mechanism](admin/history_and_snapshots.md)
  can snapshot and later reconstruct a record's exact prior shape,
  attribute node by attribute node. SHACL shapes are designed to validate
  the direct-triple style; adopting SHACL/DASH as the primary schema would
  have meant either abandoning that storage pattern (a much bigger
  redesign, touching the history mechanism along with everything else) or
  writing shapes that don't look like idiomatic SHACL anyway.

None of that rules out SHACL for the future — a SHACL shapes file
*generated from* this ontology, purely as a read-only artifact other
standards-aware tools could use to understand or validate exported data,
would be a genuinely useful, low-risk addition. It just wouldn't replace
the ontology-plus-`local:`-vocabulary approach as the thing actually
driving the running application.

## A reusable pattern, not a one-off

None of the application code described above knows anything about
projects, personnel, or publications specifically — it only knows how to
read *some* ontology and render *whatever* it finds. That means the same
codebase can become an entirely different administrative tool just by
pointing it at a different ontology and a different (empty) triple store:
a lab-equipment tracker, a grant-compliance tracker, a museum-collections
database — anything that can be described as a set of typed records with
fields — without writing new application code. The ontology is the only
thing that would need to change. That reusability is a deliberate design
goal, not an accident: build the "read an ontology, render it, store what
comes back, and let a separate history mechanism snapshot every change"
engine exactly once, well, and let it serve many different domains over
time.

## Further reading

- [VIVO Open Research Networking Community Group](https://www.w3.org/community/vivo/)
- [The CEDAR Workbench (arXiv)](https://arxiv.org/abs/1905.06480)
- [SHACL (W3C Recommendation)](https://www.w3.org/TR/shacl/)
- [Form Generation using SHACL and DASH](https://datashapes.org/forms.html)
- [Schímatos: A SHACL-Based Web-Form Generator for Knowledge Graph Editing](https://github.com/schimatos/schimatos.org)
