# Data Entry

This page covers adding and editing records as an administrator — Projects,
Personnel, and Publications all work the same way, since (per
[Philosophy & Design](../philosophy.md)) the same generic form-rendering
code drives every one of them, reading whatever the ontology currently
says a given record type looks like.

## Logging in and finding the dashboard

After logging in with an admin account (see
[Configuration](../configuration.md) for how accounts are set up), the
dashboard lists every record type this instance manages. Each one leads to
the same three actions: add a new record, search/edit existing ones (see
[Search & Queries](search_and_queries.md)), or — reached from a search
result, not from the dashboard directly — edit or delete one specific
record.

```{note}
Screenshot needed: `docs/source/_static/screenshots/admin-dashboard.png`
— the admin dashboard showing the list of record types.
```

![Admin dashboard](../_static/screenshots/admin-dashboard.png)
*The admin dashboard.*

## The form itself

Every field on an add/edit form, in the order it appears, its label, and
what kind of input it accepts, comes straight from the ontology at the
moment the page loads — nothing on this page is specific to Projects,
Personnel, or Publications; it applies equally to any record type this
instance is configured to manage, including ones that don't exist yet at
the time this is being read. A few field types show up repeatedly:

- **Plain text** — a single line or a larger text box, for anything without
  a more specific type below.
- **Date** — a date picker.
- **Currency** — a monetary amount, typed and displayed in whichever
  number format matches the current language (e.g. `1,234.56` in English,
  `1.234,56` in Spanish) — see
  [Search & Queries](search_and_queries.md#currency-fields) for how this
  also affects searching, and [Exports](exports.md) for how it appears in
  a downloaded spreadsheet.
- **Dropdown / radio buttons** — a fixed list of choices defined in the
  ontology, shown in whichever language is currently selected.
  A hierarchical variant of this (a expandable tree rather than a flat
  list) is used for a few fields where the choices are naturally organized
  in categories.
- **Cross-reference lookup** — search another record type by a
  human-readable label (e.g. a person's surname) and store a different,
  more stable value behind the scenes (e.g. their ORCID). This has its own
  page: [Cross-References](cross_references.md).

Some fields accept more than one value (for example, a publication can
have several authors) — those show up as a repeatable group of inputs
rather than a single one, with a way to add another entry.

```{note}
Screenshot needed: `docs/source/_static/screenshots/admin-add-form.png`
— an add/edit form showing a mix of field types (text, dropdown, currency,
a cross-reference lookup).
```

![Add/edit form](../_static/screenshots/admin-add-form.png)
*An add/edit form, showing several different field types.*

## Required fields and validation

Some fields must be filled in before a record can be saved (the ontology
marks which ones); trying to save without them, or with a value that
doesn't make sense for that field's type (an unparseable currency amount,
for instance), doesn't lose any work — the form reappears with a clear
banner listing every problem found, and everything already typed is still
there to fix and resubmit. Nothing is written to the database until every
field passes.

```{note}
Screenshot needed: `docs/source/_static/screenshots/admin-validation-error.png`
— a form redisplayed after a validation error, showing the error banner.
```

![Validation error banner](../_static/screenshots/admin-validation-error.png)
*A friendly validation-error banner after an invalid submission.*

## Editing and deleting an existing record

Editing an existing record starts from a search result (see
[Search & Queries](search_and_queries.md)), not from the dashboard —
opening one loads the same kind of form, pre-filled with that record's
current values. Deleting a record is available from the same place.
**Both editing and deleting are worth understanding before using them
routinely**: neither one actually destroys data — see
[History & Snapshots](history_and_snapshots.md) for what really happens
and why that matters.
