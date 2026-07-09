# Changelog

All notable changes to this project are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Entries up to and including 0.5.0 are reconstructed retroactively from git
history, since formal per-release versioning wasn't tracked from the start.
Only two versions (0.0.3 and 0.2.0) correspond to an explicit commit message;
the rest are grouped by theme/date as a best-effort mapping. From this point
forward, every release ships with a matching `VERSION` file bump and an entry
here.

## [Unreleased]

## [0.8.2] - 2026-07-09
### Fixed
- The 0.8.1 test-count badge never actually worked: it was a shields.io
  "endpoint" badge, which requires shields.io's servers to anonymously fetch
  `badges/tests.json` from this repo - impossible for a private repo (the
  fetch 404s for anyone who isn't an authenticated viewer, which is exactly
  who shields.io is). Replaced with a shields.io *static* badge, where the
  count is baked directly into the badge's own image URL instead of being
  fetched from anywhere, so it renders the same regardless of repo
  visibility. CI now rewrites that URL directly in `README.md` (and
  `badges/tests.json` is gone).

## [0.8.1] - 2026-07-09
### Added
- Second README badge showing the actual RSpec pass count (e.g. "72
  passing"), not just a generic pass/fail indicator. CI parses the RSpec
  JSON formatter's summary counts after each run on the default branch and
  commits a small `badges/tests.json` (shields.io "endpoint" format), which
  the README badge reads via `img.shields.io/endpoint`. Turns red with an
  "X/Y passing" message instead of green if any examples fail.

## [0.8.0] - 2026-07-09
### Added
- GitHub Actions CI (`.github/workflows/rspec.yml`) runs the RSpec suite on
  every push and pull request; status badge added to the README.
- RSpec regression coverage asserting every free-text search field emits an
  accent-insensitive filter, and that all six monetary project fields stay
  tagged `currency`.
### Fixed
- Accent-insensitive search had stopped matching accented values (e.g.
  searching "Maria" found none of the many accented "María" records) for
  most fields, including member name/surname. It was gated per field on an
  `ACCENT_SENSITIVE_LABELS` allowlist keyed on the ontology's human-readable
  label text, which had drifted out of sync three ways: `member_name`/
  `member_surnames` were never added; label rewording silently broke
  exact-string matches already in the list (`"affiliation"` vs. the live
  `"Affiliations"`, `"partner institutions"` vs. the live `"Partner
  institutions (acronym and country)"`); and the list was English-only, so
  it silently stopped applying under the Spanish UI too. Accent-insensitive
  matching is now unconditional for every free-text/dropdown search field,
  so there's no longer a label list to fall out of sync.
- `project_overheads` was left tagged as a plain string field instead of
  `currency` (unlike its five sibling monetary fields), so it silently
  skipped locale-aware validation, display formatting, and search
  normalization.
### Changed
- The RSpec suite's ontology source (`spec/spec_helper.rb`) now prefers a
  sibling `../CBGP-Ontology` checkout, then a live fetch from
  `https://w3id.org/CBGP-App`, before falling back to the committed
  `spec/fixtures/cbgp-application-ontology.owl` snapshot. The
  previously-frozen-only fixture is exactly what let the
  `project_overheads` mistagging above go undetected by tests.

## [0.7.0] - 2026-07-07
### Added
- SCD Type 2 history tracking (recording layer only — query/reporting layer
  and UI are designed but not yet built; see `.claude/plans/enumerated-zooming-sedgewick.md`).
  Every edit or delete of a record now snapshots its full prior state into a
  separate, dedicated GraphDB repository (`kbhistory`, new `GRAPHDB_HISTORY`/
  `HISTORY_USER`/`HISTORY_PASS` config) before the current-state graph is
  dropped/rewritten. Current-state data and behavior are completely
  unchanged — snapshots are annotated at the graph level (nanopub/PROV
  style: `prov:generatedAtTime`, `prov:invalidatedAtTime`,
  `local:history-reason`, `local:history-detail`) rather than mixed into the
  record's own data, and include a heuristic human-readable summary of what
  changed (e.g. "Total funding: 15,000.00 → 20,000.00").
- Fixed a pre-existing bug found while building the above: `dcterms:created`
  was silently lost after a record's first edit (an edit's cleanup deleted
  it and nothing rewrote it) — it's now preserved across edits.

## [0.6.0] - 2026-07-06
### Added
- Currency field type: a new `currency` ontology widget/object-class that
  stores amounts in a canonical decimal form and displays/parses them in the
  current UI language's number convention (e.g. `1,234.56` in English,
  `1.234,56` in Spanish). Applied to Project total funding.
- Mouseover help: field labels show a tooltip sourced from the ontology's
  `rdfs:comment`, when the ontology provides one, via the same bilingual
  mechanism already used for labels.
- Email notifications to admins whenever a User submits a UserFacing form
  (e.g. a new Project application), listing whichever fields were actually
  filled in. SMTP settings (host, port, TLS, auth, from address, recipients)
  are now configured via `.env` instead of hardcoded, and `NOTIFY_TO` accepts
  a comma-separated list of recipients.
- Friendly form-validation errors: an invalid field value (e.g. a bad
  currency amount) now redisplays the form with a clear error banner and the
  user's original input intact, instead of crashing with a raw exception
  page — including on the public User-facing form.
- RSpec test suite, fully offline (a frozen local snapshot of the ontology,
  no live GraphDB dependency), covering currency parsing/formatting, form
  validation-error handling, and controlled-vocabulary label resolution.
- Submit button duplicated at both top and bottom of the search and
  bulk-publication-upload forms, matching the existing add/edit forms.
### Fixed
- Multi-word accent-insensitive search (e.g. a title search containing a
  space) no longer crashes with a SPARQL lexical error.
- Search results (both the on-screen table and the Excel/TSV export) now
  show the proper language-aware label for controlled-vocabulary fields
  (select/radio/tree-selector) instead of the raw internal ontology class ID.
- `coerce_value` no longer mutates its `klass` argument in place (was
  crashing with `FrozenError` on frozen string input).
- `GET /cbgp/refresh` now actually refreshes: it previously only reloaded
  the in-memory ontology but left the per-form-type field caches stale, so
  ontology edits (e.g. marking another field as currency) silently didn't
  take effect until the whole app process was restarted.
- Fixed a crash (`NoMethodError` on `nil.capitalize`) when a User's project
  submission failed validation: the user-facing validate route never set
  `@database`, which only mattered once a validation error started
  re-rendering the form instead of the thank-you page.
- Fixed the User project form redisplaying with the *full Admin field set*
  after a validation error, instead of the restricted set of fields Users
  are actually meant to see/fill in. The route only ever had the dbname
  (e.g. `"project"`) available from the URL, not the restricted UserFacing
  questionnaire code (e.g. `"userproject"`) — a pre-existing ambiguity that
  never mattered while a failed submission just crashed, but silently built
  the wrong (Admin) questionnaire once redisplay started working. The
  correct form code is now carried through via a hidden field.
- Fixed currency validation silently accepting malformed amounts (e.g.
  `"2,00.0000"` was misread as `200.00`) by blindly stripping whatever
  character looked like a thousands separator and handing the rest to a
  float parser. Amounts are now checked against the actual expected shape
  (proper 3-digit grouping, at most 2 decimal digits) before being accepted,
  in both English and Spanish conventions.

## [0.5.0] - 2026-04-23
### Added
- Foreign-key cross-reference typeahead: fields can now search-by-label on
  another form and store a different field's value (e.g. type a member's
  surname, store their ORCiD).
- Typeahead extended to work on plain (non cross-reference) fields too.
### Removed
- Bulk delete capability (removed in favor of more deliberate per-record
  deletion after the foreign-key work made bulk deletes riskier).

## [0.4.0] - 2026-02-23 to 2026-03-05
### Added
- XML export endpoints (`/cbgp/active-members`, `/cbgp/active-emails`) feeding
  an external pipeline.
- Dataset purge utility/script.
### Fixed
- Query fixes uncovered while building the exports.

## [0.3.0] - 2026-02-02 to 2026-02-08
### Added
- Bulk loader for member/personnel records.
- Multi-instance tree-selector widget (works with more than one tree selector
  per questionnaire).
### Changed
- Performance optimization: batched SPARQL queries instead of per-record
  round-trips.
- Pinned Ruby to 3.2.4 for deployment compatibility.

## [0.2.0] - 2025-12-29 to 2025-12-30
### Added
- Bulk delete capability for search results (explicit commit: "version
  0.2.0.with bulk delete").
### Fixed
- Various bug fixes; tree display now works together with search.

## [0.0.7] - 2025-12-19 to 2025-12-29
### Added
- Public/user-facing forms distinct from the admin interface; role-based
  (admin vs. user) access control.
- Bulk publication loader with duplicate detection based on existing external
  identifiers (DOIs).
### Changed
- Refactored permanent identifiers and named-graph handling so edits reuse
  the existing graph URI instead of creating duplicates.
- Search results can now be edited directly and downloaded to Excel.

## [0.0.6] - 2025-09-30 to 2025-10-27
### Added
- Tree-selector (hierarchical) widget for controlled vocabularies.
- Search-dataset forms (query by field, paginated results).
- STATUS, FPI, partner-institution, and call-for-proposal fields.
### Fixed
- Multi-value ("Multiple" cardinality) field handling across load/search/save.

## [0.0.5] - 2025-08-15 to 2025-09-15
### Added
- Staff/personnel database and its ontology-driven form.
- Countries controlled-vocabulary list.
- Spanish translation; multilingual (en/es) rendering throughout.
- All three databases (staff, project, publication) rendering end-to-end for
  the first time.

## [0.0.4] - 2025-05-07 to 2025-05-27
### Added
- Full DataCite/OpenAIRE citation lookup and preformatted citation box.
### Changed
- Dockerized the app.
- More resilient DataCite API calls; basic date sanity checks; fixed SASS
  (Compass) stylesheet compilation.
- Docker image tagged `v0.0.3` at this point.

## [0.0.2] - 2025-01-27 to 2025-03-19
### Added
- First ontology-driven database portal: forms, fields, and widgets generated
  at runtime from the OWL knowledgebase instead of being hand-coded.
- Read/write to the triple store (SPARQL) with round-trip record editing.
- Author/affiliation list widgets for publications.
- Semantic data models (drawio diagrams) for staff, project, and publications.

## [0.0.1] - 2024-12-20 to 2025-01-08
### Added
- Initial commit; first exploratory Project and Staff data models.
- Raw HTML form prototypes and CSV-based data capture, pre-ontology.

[Unreleased]: https://github.com/CBGP-UPM-INIA-PUBLIC/CBGP-Databases/compare/v0.8.2...HEAD
[0.8.2]: https://github.com/CBGP-UPM-INIA-PUBLIC/CBGP-Databases/compare/v0.8.1...v0.8.2
[0.8.1]: https://github.com/CBGP-UPM-INIA-PUBLIC/CBGP-Databases/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/CBGP-UPM-INIA-PUBLIC/CBGP-Databases/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/CBGP-UPM-INIA-PUBLIC/CBGP-Databases/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/CBGP-UPM-INIA-PUBLIC/CBGP-Databases/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/CBGP-UPM-INIA-PUBLIC/CBGP-Databases/commits/main
