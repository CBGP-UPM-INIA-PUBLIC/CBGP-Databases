# Personnel matcher stress test (2026-08-26)

Real-data validation of `lib/personnel_matcher.rb`'s name-matching rule
(`CBGP::Parsers.find_member_by_name`), run against all 272 real `member`
records loaded via `utilities/personnel_loader.rb` from
`personal_CBGP_orcids.csv`. No names or other PII are recorded in this
document — only aggregate counts.

## Why

`find_member_by_name` is the fallback used by
`CBGP::Parsers.match_authors_to_personnel` (called from the DOI/publication
loader in `lib/loaders.rb`) to attribute a publication's authors to existing
CBGP personnel when the author record carries no ORCID. Before this test,
the rule required an *exact* full given-name + full surname match (after
stripping accents). The real personnel data was never checked against that
assumption end-to-end.

## Personnel data shape (272 real records)

| Stat | Value |
|---|---|
| Given-name token count distribution | `{1=>218, 2=>51, 3=>1, 4=>1, 6=>1}` |
| Surname token count distribution | `{2=>223, 1=>41, 3=>5, 4=>2, 5=>1}` |
| Records with at least one accented character | 172 / 272 |
| Records missing `member_dni_nie_pas` | 0 / 272 |
| Records missing `member_cbgp_id` | 0 / 272 |
| Duplicate `member_dni_nie_pas` values | 0 |

Most CBGP staff (223/272) carry a Spanish double surname, and a fifth
(51/272) carry a compound given name. Both are exactly the shapes that
DOI-registry metadata (Crossref, DataCite, OpenAIRE) routinely truncates.

## Method

For each of the 272 real records, the stored `name`/`surname` was degraded
to simulate registry truncation: only the **first given-name token** and
**first surname token** were kept. The degraded (given, family) pair was
then run through `find_member_by_name` against the full 272-record index,
and the result was checked against the original record's identity.

## Result: old rule (exact full-string match)

| Outcome | Count |
|---|---|
| Self-match on untouched name/surname | 272 / 272 |
| Correct match after degradation | 33 / 272 |
| No match found (false negative) | 239 / 272 (88%) |
| Matched to the wrong person (false positive) | 0 / 272 |

Zero collisions, but an 88% miss rate under realistic truncation — the exact
full-string rule was far too strict to be useful for this personnel list.

## Decision

Loosened the rule (2026-08-26) to: given name matches on its **first token**
only; surname matches if **any token** overlaps between the two sides. This
is still exact-token matching, not fuzzy string similarity.

Accepted rationale: `match_authors_to_personnel` only ever runs against the
author list of a publication already known to include at least one real
CBGP co-author — the risk being guarded against is under-matching a known
person, not a random collision against an arbitrary stranger. See
`lib/personnel_matcher.rb`'s doc comment for the full reasoning.

## Result: new rule (loosened, first-token given + any-token surname)

| Outcome | Count |
|---|---|
| Self-match on untouched name/surname | 272 / 272 |
| Correct match after degradation | 267 / 272 |
| No match found (false negative) | 0 / 272 |
| Matched to the wrong person (false positive) | 5 / 272 (1.8%) |

## Are the 5 collisions a matcher bug?

No — checked structurally. Among the 272 real records, **9 pairs** of
different people genuinely share the same given-name first token *and* at
least one surname token (e.g. two different people both named, say, "Juan
[something] García"). This is irreducible ambiguity in the personnel data
itself: no algorithm operating on a truncated name alone can distinguish
between them without additional context (ORCID, DNI, or a human checking
the source publication). The 5 observed collisions are a subset of these 9
genuinely ambiguous pairs; the other 4 didn't manifest as an error in this
particular test run, depending on which of the two names happened to get
degraded and matched first.

## Net effect

| | Old rule | New rule |
|---|---|---|
| Correct | 33/272 (12%) | 267/272 (98%) |
| Missed | 239/272 (88%) | 0/272 (0%) |
| Wrong person | 0/272 (0%) | 5/272 (1.8%) |

Traded an 88% miss rate for a 1.8% collision rate, where the collisions are
pre-existing name ambiguity in the real data rather than algorithmic error —
consistent with the original design's fallback expectation that unmatched
(or, now, occasionally mismatched) authors get corrected by hand.

## Reproducing this test

The test scripts used are throwaway (not committed, run from a scratch
directory against a live local Virtuoso instance) — they:

1. Load all `member` graphs via `execute_search(dataset_type: 'member', broad: true)`.
2. Degrade each record's `name`/`surname` to first-token-only.
3. Run the degraded pair through `CBGP::Parsers.find_member_by_name` and
   compare the result's identity to the original record.

No PII was printed to any log during this test — only aggregate counts and
graph URIs (which contain only UUIDs, no personal data).
