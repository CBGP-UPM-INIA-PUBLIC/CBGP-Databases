# Cross-References

## What a cross-reference field is

Some fields don't hold a value typed directly into them — instead, they
point at *another* record entirely. The clearest example is a
publication's author: rather than typing a name into a text box (which
would create a new, disconnected piece of text every time, with no way
to tell that "M. García" and "María García" on two different
publications are the same person), the field searches the actual
Personnel records and links to one of them.

This shows up on both the add/edit forms described in [Data
Entry](data_entry.md) and the search forms described in [Search &
Queries](search_and_queries.md) — the same lookup works the same way in
both places.

## How the lookup works

Typing into a cross-reference field searches the target record type by a
human-readable label — a person's surname, for instance — and shows
matching suggestions as options to pick from. Choosing one fills in the
field, but what actually gets stored behind the scenes is a different,
more stable value than the text that was searched for — an ORCID for a
person, for example, rather than their name. This matters because names
change, get spelled differently, or coincide between different people,
while the stored identifier doesn't; it also means every record that
links to the same person or project genuinely links to the *same* thing,
not just to text that happens to look similar.

```{note}
Screenshot needed:
`docs/source/_static/screenshots/admin-xref-typeahead.png` — a
cross-reference field mid-search, showing the dropdown of matching
suggestions as text is typed.
```

![Cross-reference typeahead](../_static/screenshots/admin-xref-typeahead.png)
*A cross-reference field, showing suggestions while typing.*

## What this means in practice

- **Search by whatever's easiest to remember, not by an ID.** There's
  never a need to know or type an ORCID, an accession number, or any
  other behind-the-scenes identifier by hand — searching by name (or
  whatever label the field is set up to search by) is always enough.
- **A field can accept more than one link.** A publication with several
  authors, for example, offers a repeatable set of these lookups, one per
  author — the same "add another entry" behavior mentioned in [Data
  Entry](data_entry.md).
- **The record being linked to must already exist.** If a search doesn't
  find the person or project being looked for, that record needs to be
  created first (see [Data Entry](data_entry.md)) before it can be
  cross-referenced from somewhere else — a cross-reference field can't
  create the thing it's pointing at on the fly.
