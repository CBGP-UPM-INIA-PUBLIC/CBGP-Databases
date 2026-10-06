# Cross-References

## What a cross-reference field is

Some fields don't hold a value typed directly into them — instead, they
point at *another* record entirely. The clearest example is a
publication's author: rather than typing a name into a text box (which
would create a new, disconnected piece of text every time, with no way
to tell that "M. García" and "María García" on two different
publications are the same person), the field searches the actual
Member records and links to one of them.

This shows up on both the add/edit forms described in [Data
Entry](data_entry.md) and the search forms described in [Search &
Queries](search_and_queries.md) — the same lookup works the same way in
both places.

## How the lookup works

Typing into a cross-reference field searches the target record type by a
human-readable label — a person's surname, for instance — and shows
matching suggestions as options to pick from. Choosing one fills in the
field, but what actually gets stored behind the scenes is a different,
more stable value than the text that was searched for — a DNI/NIE/PAS number
(or, for a publication's authors, an ORCID) for a person, for example, rather than
their name. This matters because names
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

## The DOI importer's automatic member matching

The single-DOI and bulk-DOI importers (under **Data Loaders** on the main
menu) don't just fetch a publication's title, journal, and author list from
DataCite, Crossref or OpenAIRE — whichever agency registered the DOI — they
also try to work out which of those authors are CBGP members, and link the
ones that match. A DOI can be typed bare (`10.1000/xyz`) or pasted as a
resolver link (`https://doi.org/10.1000/xyz`); the link prefix is removed
automatically, and a DOI that is already in the system is not loaded twice.

An author is matched to a member in one of two ways, tried in this order:

1. **By ORCID** — an exact match against the ORCID on a member record.
2. **By name**, when there is no ORCID match — the first word of the given
   name must be the same, and at least one word of the surname must be the
   same, ignoring accents and capital letters (so a paper's "Garcia"
   matches the member record's "García", and a truncated "María García"
   matches "María del Carmen García López").

Only a member who **has an ORCID recorded** can be linked this way, because
the "CBGP Author(s)" field on a publication stores the member's ORCID (unlike
the person fields on projects, which store the DNI/NIE/PAS).

```{important}
**This matching can only find member records that already exist.**
If members haven't been loaded into the system yet — or a particular
author's member record hasn't been created yet — the importer will still load
the publication itself correctly (title, journal, authors, etc.), but it will
link **zero** CBGP authors, even for a paper written entirely by CBGP staff.
There is no error or warning when this happens; the "CBGP Author(s)" field is
simply left empty.

**Practical consequence:** load the members *before* relying on the DOI
importer's automatic author linking. Importing publications first and members
second means every publication loaded in that window will need its author
links added by hand afterwards — the importer does not go back and retry once
the members exist.

If member data won't be loaded for a while, or a specific author is never
going to have a member record (an external co-author, for example), the
"CBGP Author(s)" cross-reference on a publication can always be added or
corrected manually afterwards, the same way any other cross-reference field is
edited (see [Data Entry](data_entry.md)) — the importer's matching is a
convenience, not the only way to set this field.

**The name rule is looser than an exact full-name match, deliberately.**
Journals and DOI agencies routinely shorten names, and most staff have two
surnames or a compound given name, so requiring the whole name to match missed
most real authors when this was tried on the institute's actual records. The
price is that two *different* members who share a first name and a surname
word could be confused with each other; an ORCID match, when there is one, is
always unambiguous. Check the linked authors on a publication where it
matters, and correct them by hand if needed.
```
