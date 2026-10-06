# Search & Queries

## Finding the search screen

Every record type reachable from the dashboard (see [Data
Entry](data_entry.md)) has its own search screen, built the same
ontology-driven way as the add/edit forms — the fields offered for
searching, and what kind of input each one accepts, come from the same
source and follow the same rules described in [Data
Entry](data_entry.md)'s "The form itself" section. Filling in one field
and leaving the rest blank searches on that field alone; filling in
several searches for records matching *all* of them at once — there's no
way to search for "either this or that" within a single search.

```{note}
Screenshot needed: `docs/source/_static/screenshots/admin-search-form.png`
— a search screen showing a mix of field types, and a results list below
it.
```

![Search form](../_static/screenshots/admin-search-form.png)
*A search form, with results shown below.*

## Searching every kind of project at once

Some record types come in several kinds that are stored together: a
project can be a European, a National/Regional, a Private or a Personnel
Project, each with its own add/edit form and some fields of its own, but
all of them are *projects*, and a question like "what projects are running
now?" does not care which kind a project is. For every group of forms
stored together like this, the **Query Data** list on the dashboard has one
extra entry, named after the group — **Projects (all types)**. It appears
only in the Query Data list: it is a way of *searching*, not a form, so it
is never offered under Add Data.

Its search screen offers only the fields that **every** kind has in common
(title, internal code, application URL, PI, start date, end date, status,
and so on), since a field that only some kinds have can't be asked of a
group that includes the others. The results list then shows those same
fields, plus a **Record type** column saying which form wrote each record
(see [Reading the results](#reading-the-results) below). Opening a record
from that list always opens it under its own form, with all of that form's
fields — see [Data Entry](data_entry.md#editing-and-deleting-an-existing-record).

```{note}
Screenshot needed: `docs/source/_static/screenshots/admin-all-types-search.png`
— the dashboard's Query Data dropdown open, showing "Projects (all types)"
among the single-form entries.
```

![The all-types entry in the Query Data list](../_static/screenshots/admin-all-types-search.png)
*The all-types entry appears alongside the individual forms in Query Data.*

**For the ontology editor:** nothing needs declaring for this to work — the
application adds the entry for any storage name (`local:dbname`) that more
than one *Core* form uses. Only the entry's *name* is text you can set: add
an interface text (see [Data Model](../data_model.md#interface-text-lives-in-the-ontology))
called `ui_dbname_<name>` — `ui_dbname_project` is what gives "Projects (all
types)" and "Proyectos (todos los tipos)". Without one, the entry is called
"`<name>` (all types)". The forms offered for the common fields are the
ones in the same list as Add Data; a cut-down form that members fill in
themselves (see [User Guide](../user_guide.md)) stores under the same name
but is not counted, so it does not shrink the list of common fields. Its
records still appear in the results, with blanks where it has no such field.

## Listing everything

Every search screen has a **Show all records** link at the top. It lists
every record of that type, ignoring anything typed into the form.

Submitting the form with every box empty does **not** do this, on purpose:
it says "Nothing was entered to search for" and offers the Show all link.
A stray press of Enter on a record type with hundreds of rows would
otherwise start a very large listing, and a blank search is far more often
a mistake than a request.

```{note}
Very long lists are slow to build. When this was written, listing every
Member (several hundred records) took on the order of tens of seconds,
because the application builds the whole page in one go; paging the results
is not implemented yet.
```

## Text searches are partial and accent-insensitive

A text search doesn't require typing the whole value, and doesn't
require getting accents right. Both of the following behave the way most
people expect rather than the way a database literally stores things:

- **Partial matches.** Searching `garcía` finds *"María García López"* —
  the search term just has to appear somewhere in the value, not match it
  exactly.
- **Accent-insensitive matches.** Searching `maria` finds *"María"*, and
  searching `maría` also finds plain *"Maria"* — accented and unaccented
  letters are treated as equivalent in both directions, in every
  language. There's no separate "ignore accents" checkbox to remember to
  tick; this is simply how every text search works.

This applies uniformly to every free-text and dropdown-choice field
across every record type — there's no list of fields where it does or
doesn't apply.

(currency-fields)=
## Currency fields

A currency field's search box accepts a number typed in whichever format
matches the currently selected language (see the language switch
mentioned in [Philosophy & Design](../philosophy.md)) — for example
`15,000.50` in English or `15.000,50` in Spanish — and finds records
whose value, once normalized to the same underlying stored form, contains
what was typed. Typing `15000` matches a stored value of `15,000.50`; it
does **not** search for an amount greater than or less than the number
typed — there's no "at least" / "at most" range search on currency
fields, only this kind of value match. See
[Exports](exports.md#currency-in-spreadsheets) for how the same
underlying value later appears in a downloaded spreadsheet.

## Date fields

A date field offers two boxes, a start and an end, either of which can be
left blank: filling in only a start finds everything on or after that
date, filling in only an end finds everything on or before it, and
filling in both finds everything in between (inclusive on both ends).

Dates are kept as real dates, not as text (see [Data
Model](../data_model.md#how-values-are-typed)), which is what makes these
comparisons reliable. A date that is not a real calendar date — `30
February`, say — is refused when a record is saved rather than stored as
something that looks like a date but would compare wrongly.

**`today`.** In a saved link or bookmark — not in the date picker — a date
may be written as the word `today`, meaning the day the search is *run*
rather than the day the link was made. That is what lets a bookmarked
"running now" search stay correct next week. See [What is running
now?](#what-is-running-now) below for the recipe it was made for.

(excluding-matches)=
## Excluding matches, and "or no value"

Next to every field on a search screen are two tick boxes that change how
that one field is used:

- **NOT (exclude matches)** turns the field around: it finds the records
  that do **not** match what was typed — *including* records where the
  field is empty, since "doesn't match" is true of them too.
- **or no value** widens the field the other way: it finds records that
  match what was typed **or** that have no value in that field at all.

All the fields on a search screen are still combined with *and*; these two
boxes are the only way to say "or" or "not", and each applies to the one
field it sits beside. If both are ticked on the same field, NOT wins (the
two would contradict each other).

(what-is-running-now)=
## What is running now?

"Currently running" means a project that **has started** and **has not
ended** — and a project with no end date counts as not having ended. That
is two date conditions and one "or no value":

Each date field on the search screen has two boxes, labelled **Start
Date** and **End Date** (the beginning and end of the range being asked
about — not to be confused with the project's own start and end dates):

1. In the project's **Start date** field, fill in only the second box
   (*End Date*) with today's date: *started on or before today*.
2. In the project's **End date** field, fill in only the first box (*Start
   Date*) with today's date: *ends on or after today*. Then tick **or no
   value** beside that field: *or has no end date at all*.
3. Optionally, set **Funding status** to narrow it further — `Awarded` for
   what is actually funded, say.

Run on **Projects (all types)** this answers the question whichever kind
of project each one is. The same search, written as a link that is always
"as of today":

```text
/cbgp/query-dataset/project?project_start_date[end]=today&project_end_date[start]=today&project_end_date__orempty=1
```

"Which projects are pending an award?" is the same idea with a different
field: **Funding status** set to `Proposed`, and nothing else.

Two things are deliberately *not* in the results. A project that has not
started yet is not running, and a project submitted by a member through the
user-facing form (see [Data Entry](data_entry.md#curating-a-project-submitted-by-a-member))
has no start date until someone curates it and it is awarded — so it will
not appear here, and that is correct, not a gap. Search by **Funding
status** to find those.

## Cross-reference fields

Fields that link to another record type (for example, searching
Publications by an author's name) work the same searchable, typeahead way
they do when adding or editing a record — see
[Cross-References](cross_references.md) for the full explanation of how
the lookup works.

(reading-the-results)=
## Reading the results

Results appear as a list below the search form. Opening one from the
list is also how an existing record is reached for editing or deleting —
see [Data Entry](data_entry.md)'s "Editing and deleting an existing
record" section, and [History & Snapshots](history_and_snapshots.md) for
what those two actions really do. The same result list is also the
starting point for a spreadsheet export — see [Exports](exports.md).

**Record type.** Every results list has a **Record type** column naming
the form that wrote each record ("Personnel Project", "National and
Regional Research Projects", …) — it is what tells the kinds apart in an
all-types search. Records written before the application kept this
information show it blank. The name is itself a link to a search listing
every record of that form.

**Every value is a link.** Most values in the list are links, and every one
does the same thing: it searches the same record type for records holding
**exactly** that value. Click a funding institution to see every project it
funds; click a status to list everything with that status. (A search typed
into the form matches "contains this text"; a link matches the whole value —
a link on one DNI must not also find every other DNI that happens to
contain those digits.) The result is an ordinary results page, so you can
keep narrowing from there.

- A value that points at *another* record — a PI, a member — links to the
  search of that other record type for that person, so one click takes you
  from a project to the person.
- Values that are not looked up by their exact content stay plain text:
  free-text and multi-line notes, numbers and amounts, and dates (use the
  range boxes for those). Web addresses are already links to their own page.

On the **edit page**, an administrator also sees a small arrow beside each
field that has a stored value; it opens the same exact-match search for that
value in a **new window**, so unsaved changes on the page are not lost.
The arrow always uses the value *saved* in the record, not what is
currently typed in the box.

Every such link is a plain address of the form
`/cbgp/query-dataset/<record type>?<field>=<value>&<field>__exact=1`, so the
same search can be saved as a bookmark or pasted into an email.
