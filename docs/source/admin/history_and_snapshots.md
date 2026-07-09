# History & Snapshots

## Edits and deletions look destructive, but aren't

When an administrator edits a record and saves, or deletes one outright,
the record's *current* version really does disappear from the normal
search results described in [Search & Queries](search_and_queries.md) —
there is no "undo" button, and no trash/recycle bin to look in. In that
sense, both actions are genuinely destructive to the record as it
currently appears.

What isn't obvious from the screen is that, immediately before either of
those things happens, the application copies the record's *entire*
current version — every field, exactly as it stood — into a second,
separate database kept only for this purpose, and stamps that copy with
when it was replaced and why. Nothing about editing or deleting skips
this step; it's not a setting that can be turned off. So while the
*current* version is genuinely gone, nothing about the record is ever
actually lost.

```{note}
This project follows a well-established database design pattern for
exactly this situation, sometimes called "Slowly Changing Dimension"
(SCD) history-tracking — the same idea data warehouses have used for
decades to answer "what did this look like at some point in the past?"
without cluttering the live data with old versions.
```

## Why keep the two separate

The two databases have different jobs, and keeping them physically
separate (rather than, say, marking old rows as "inactive" inside one
database) is deliberate:

- The **current** database (see [Installation](../installation.md)) only
  ever holds today's truth. Every search, form, and export described
  elsewhere in this guide reads only from here — old versions can never
  accidentally show up mixed in with current data, because they simply
  aren't in this database at all.
- The **history** database accumulates a permanent, append-only record of
  every version a record has ever had, along with a short, automatically
  generated summary of what changed at each step (for example, *"Total
  funding: 15,000.00 → 20,000.00"*) — the same kind of value formatting
  used everywhere else in the application, including currency and
  controlled-vocabulary labels.

## What this means day to day

- **It's safe to correct mistakes.** Editing a record to fix a typo, or
  deleting a record that was created in error, doesn't erase anything —
  the previous version is preserved automatically, with no extra step to
  remember.
- **There's no in-app screen (yet) for browsing a record's past
  versions.** The history is fully captured and safe from the moment it's
  created, but reviewing it today means using the small set of read-only
  API calls covered in [Time Travel](../time_travel.md) — useful for
  answering a specific question (*"who worked on this project in 2019?"*)
  rather than for casual browsing.
- **Nothing here is a substitute for normal judgment when deleting a
  record.** The data isn't destroyed, but a deleted record also won't
  reappear in searches or exports on its own — deleting something that
  turns out to still be needed means either re-entering it or asking
  whoever manages the database directly to retrieve the relevant version
  from the history side.
