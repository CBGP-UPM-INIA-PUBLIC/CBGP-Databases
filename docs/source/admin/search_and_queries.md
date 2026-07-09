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

## Cross-reference fields

Fields that link to another record type (for example, searching
Publications by an author's name) work the same searchable, typeahead way
they do when adding or editing a record — see
[Cross-References](cross_references.md) for the full explanation of how
the lookup works.

## Reading the results

Results appear as a list below the search form; opening one from the
list is also how an existing record is reached for editing or deleting —
see [Data Entry](data_entry.md)'s "Editing and deleting an existing
record" section, and [History & Snapshots](history_and_snapshots.md) for
what those two actions really do. The same result list is also the
starting point for a spreadsheet export — see [Exports](exports.md).
