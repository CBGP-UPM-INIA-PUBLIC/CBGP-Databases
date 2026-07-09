# Time Travel

## What this is

[History & Snapshots](admin/history_and_snapshots.md) explained that
editing or deleting a record never actually loses data — a complete copy
of the previous version is kept, permanently, in a separate history
database. This page covers the small set of read-only HTTP calls that
can actually retrieve that history: given a record's identifier, or a
question about a point (or period) in the past, these return the
matching data directly as JSON — no admin screen, no login form, just a
URL that returns an answer.

This is written for whoever is comfortable making an HTTP request —
typically from a Jupyter notebook, but any tool or programming language
that can make a web request works identically. Two ready-to-run notebook
examples are linked at the bottom of this page.

## Two kinds of question

Everything on this page answers one of two shapes of question:

- **"What is the complete history of *this specific* record?"** — every
  version a single record has ever had, from creation to today (or to
  its deletion), in order.
- **"What matched *some condition* during a period of time, and
  optionally, what does that add up to?"** — for example, every project
  of a certain type that was active at some point in a date range, and
  optionally the total of some numeric field across all of them.

Both are read this way (not by browsing) precisely because there's no
in-app screen for this yet — see [History &
Snapshots](admin/history_and_snapshots.md#what-this-means-day-to-day).

## Worked example 1: a single record's full history

*"Show me everything that's ever been recorded about the member with
ORCID 0000-0002-1234-5678."*

```
GET /cbgp/history/member/member_orcid/0000-0002-1234-5678
```

The three parts after `/cbgp/history/` are: which kind of record
(`member`), which field identifies it (`member_orcid`), and the value to
look it up by — the same field a cross-reference lookup would search by
(see [Cross-References](admin/cross_references.md)). The response is a
timeline: one entry per version that record has ever had, each carrying
its own fields exactly as they were at that time, plus *when* that
version was replaced and *why* (the same short change summary described
in [History & Snapshots](admin/history_and_snapshots.md)). If the record
was later deleted, its last version is still included — deletion removes
a record from current search results, not from its own history.

A shortened example of what comes back (real responses include every
field the ontology defined for that record at each point in time, not
just these):

```json
{
  "@context": {"cbgp": "https://w3id.org/CBGP-App#",
               "local": "urn:local:",
               "prov": "http://www.w3.org/ns/prov#"},
  "@graph": [
    {
      "@id": "urn:local:query-result-...",
      "@type": "local:TimeMachineResult",
      "local:queryType": "record-history",
      "cbgp:member_orcid": "0000-0002-1234-5678",
      "local:version": [
        {"@id": ".../member/history/.../v1"},
        {"@id": ".../member/history/.../v2"}
      ]
    },
    {
      "@id": ".../member/history/.../v1",
      "prov:generatedAtTime": "2024-03-01T09:12:00Z",
      "prov:invalidatedAtTime": "2024-11-15T14:03:00Z",
      "local:history-reason": "superseded",
      "local:history-detail": "Member status: Active → Inactive"
    }
  ]
}
```

## Worked example 2: a question about a period of time

*"Across every Articulo-60 project that was active at some point in the
first half of 2025, what was the total funding — even counting ones that
have since been deleted?"*

```
POST /cbgp/query-history/project
Content-Type: application/x-www-form-urlencoded

project_type=Articulo-60
&project_start_date[start]=2025-01-01
&project_start_date[end]=2025-06-30
&sum_field=project_total_funding
```

The facet parameters (`project_type=...`, a date-range field given as
`[start]`/`[end]`) work exactly like filling in the search form covered
in [Search & Queries](admin/search_and_queries.md) — any field on that
form can be used as a facet here the same way. `sum_field` is optional:
leave it out to get back the list of matching records without a total.
Because this reads from the history database rather than the current
one, a project that matched the criteria and was later deleted is still
found and still counted — this is the whole point of keeping history in
the first place, not an incidental side effect.

```json
{
  "@graph": [
    {
      "@type": "local:TimeMachineResult",
      "local:queryType": "temporal-aggregate",
      "local:recordCount": 4,
      "local:summedField": "project_total_funding",
      "local:totalAmount": "35000.00",
      "local:contributingRecord": [
        {"@id": ".../project/history/.../a"},
        {"@id": ".../project/current/.../b"}
      ]
    }
  ]
}
```

## Output format

Both endpoints default to JSON-LD (plain JSON with a `@context`, readable
by any JSON tool even without understanding what JSON-LD is). Adding
`?format=trig` to either URL returns TriG instead (Turtle's triple
syntax, plus named blocks marking which triples came from which
snapshot) — useful for RDF-aware tools that want to keep each
contributing version distinguishable. Plain Turtle isn't offered as an
option: a result can combine several versions of the same record, and
Turtle has no way to keep same-named fields from different versions
apart once they're combined — TriG's named-graph blocks solve exactly
that.

## Discovering what fields exist

*"What fields does a Project record have, and what are the legal values
for its type field?"*

```
GET /cbgp/facets/project
```

This returns the same field list and controlled-vocabulary options the
add/edit and search forms themselves are built from (see [Philosophy &
Design](philosophy.md)) — useful for writing a query without first
having to open the search form and read off the field names by hand.

## Try it yourself

```{note}
Notebook needed: save a working example as
`docs/source/notebooks/member_history_example.ipynb`, covering worked
example 1 above, then add the following directive right here in this
page (see `docs/source/notebooks/README.md` for the full instructions):

    {jupyterlite} member_history_example.ipynb
    :width: 100%
    :height: 600px
```

```{note}
Notebook needed: save a working example as
`docs/source/notebooks/funding_aggregate_example.ipynb`, covering worked
example 2 above, then add the following directive right here in this
page:

    {jupyterlite} funding_aggregate_example.ipynb
    :width: 100%
    :height: 600px
```

Once added, each notebook runs live in the browser (a real Python
kernel, via [JupyterLite](https://jupyterlite.readthedocs.io/)) — a
reader can open this page and run the exact examples above themselves,
with no installation.
