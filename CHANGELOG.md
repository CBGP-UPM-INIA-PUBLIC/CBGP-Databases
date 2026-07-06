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

[Unreleased]: https://github.com/CBGP-UPM-INIA-PUBLIC/CBGP-Databases/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/CBGP-UPM-INIA-PUBLIC/CBGP-Databases/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/CBGP-UPM-INIA-PUBLIC/CBGP-Databases/commits/main
