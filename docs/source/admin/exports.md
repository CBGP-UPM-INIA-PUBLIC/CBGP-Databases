# Exports

## Downloading search results

Every search result list described in [Search &
Queries](search_and_queries.md) has a **"Download to Excel"** link above
it, which appears as soon as a search returns at least one result. It
downloads every currently-displayed result, with every column that's
shown on screen, as a single file named
`cbgp-search-results-<database>-<date>.tsv`.

```{note}
Screenshot needed:
`docs/source/_static/screenshots/admin-export-link.png` — a search
results table with the "Download to Excel" link visible above it.
```

![Download to Excel link](../_static/screenshots/admin-export-link.png)
*The download link, shown above a set of search results.*

The downloaded file opens directly in Excel (or any other spreadsheet
program) by double-clicking it — no import wizard or file-format prompt
needed. Behind the scenes it's a tab-separated text file rather than
Excel's own native format; this is a deliberate choice, not a
limitation — it sidesteps a whole category of problems where a
number or date gets silently misread because Excel guessed the wrong
regional format for a comma- or period-separated file. Tab-separated
files don't have that ambiguity, so Excel reads every column correctly
regardless of which regional settings it's running under.

(currency-in-spreadsheets)=
## Currency in spreadsheets

Every currency value in an export is written out already formatted the
same way it appears on screen in the current interface language — for
example `1,234.56` if the interface is in English at the moment the
export is downloaded, or `1.234,56` if it's in Spanish (see [Search &
Queries](search_and_queries.md#currency-fields) for the same formatting
rule as it applies to searching). Switching the language and downloading
the same search again produces a file with the same numbers written the
other way — nothing about the underlying data changes, only how it's
displayed.

```{note}
Because the exported number is already formatted as text (to guarantee
it reads correctly regardless of regional settings), Excel may treat a
currency column as text rather than as a number it can sum or chart
directly. Reformatting a column as a number after opening the file — a
normal spreadsheet operation — resolves this if further calculation is
needed.
```

## What gets exported

The export contains exactly the columns currently shown in the results
table — the same fields, in the same order, with the same
controlled-vocabulary labels and cross-reference values already resolved
to their readable form (see [Cross-References](cross_references.md)) —
plus one extra first column identifying which record each row belongs
to. A field that holds more than one value (see [Data
Entry](data_entry.md)) exports all of them in a single cell, separated by
commas.
