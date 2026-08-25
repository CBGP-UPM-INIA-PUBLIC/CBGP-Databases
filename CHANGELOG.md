# Changelog

All notable changes to this project are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Entries up to and including 0.5.0 are reconstructed retroactively from git
history, since formal per-release versioning wasn't tracked from the start.
Only two versions (0.0.3 and 0.2.0) correspond to an explicit commit message;
the rest are grouped by theme/date as a best-effort mapping. From this point
forward, every release ships with a matching `VERSION` file bump and an entry
here.

## [0.17.0] - 2026-08-25
### Fixed
- Test fixtures updated to match Sara's project-fields ontology
  restructuring (the old shared `project` form, distinguished by
  `dcterms:type`, replaced by `european_research_project`/
  `national_regional_research_project`/`private_research_project`/
  `personnel_project`): `display_labels_spec.rb`, `dcterms_type_spec.rb`,
  `history_capture_spec.rb`, `dataset_classes_currency_spec.rb`,
  `search_accent_spec.rb`, `form_required_fields_spec.rb`,
  `form_defaults_spec.rb`, `form_formulas_spec.rb` all re-anchored to real
  fields on the new forms. Confirmed the application itself has zero
  hardcoded field names anywhere in `lib/`/`app/` - only these test
  fixtures needed updating; the ontology-driven design held.
- A project-wide ontology sanity/validation pass ahead of the beta
  release, checking every form's `local:requires-field`/`local:has-formulas`/
  `local:has-defaults` targets actually resolve, plus every formula's
  Dentaku variable names against real fields. Found and fixed 5 real,
  entirely silent bugs directly in `CBGP-Ontology` (`59d1a2f`, `8870fc7`) -
  none of these ever raised an error, which is exactly why a systematic
  audit was needed rather than relying on the test suite alone:
  - `project_funding_entity` (required on Personnel Project) was missing
    `local:question-order`, so it never rendered or got enforced.
  - Private Research Projects' required-field list pointed at National/
    Regional Research Projects' funding-institution field instead of its
    own - could never have been satisfied as written.
  - European Research Projects' overheads formula referenced a variable
    name matching no real field (naming drift).
  - One formula-definition resource was shared verbatim by European and
    Private Research Projects for `project_cbgp_overheads`, but each
    form's own "total overheads" field has a different name - split into
    two per-form formula resources. Side effect: European Research
    Projects now has a genuine two-step calculation chain
    (`total_funding → total_overheads → project_cbgp_overheads`), which
    `form_formulas_spec.rb` exercises directly with no mocking.
  - National/Regional Research Projects' year 1-4 overheads formulas
    referenced over-prefixed variable names matching no real field.
- `form_defaults_spec.rb`: the ontology's last real `local:has-defaults`
  example was removed by Sara's "clean test fields" pass, leaving that
  mechanism with zero live users. Rather than reintroduce a disposable
  sandbox field purely to keep a test anchored to "real" content (which is
  what kept breaking across two ontology restructuring passes), this spec
  now tests the SPARQL query layer against a small synthetic in-memory
  ontology and the application layer against real fields with a stubbed
  default - decoupling it from future ontology churn permanently.

Full suite: 203 examples, 0 failures, stable across multiple random seeds.

## [0.16.0] - 2026-08-25
### Changed
- **Switched from GraphDB to Virtuoso** as the triplestore, both for the
  current-state store and the SCD history store. Trigger: GraphDB's
  free/open tier returned to requiring periodic license re-registration.
  Verified live against a real Virtuoso 07.20 container (write, read-back,
  and history-snapshot round trips) before committing to the switch.
  - Unlike GraphDB (one server process hosting multiple named
    repositories), a single Virtuoso process is one quad store - so the
    current-state and history stores, kept *physically* separate on
    purpose (see `configuration.rb`), are now two separate Virtuoso
    containers/processes rather than two repositories in one GraphDB
    instance. `docker-compose.yml` runs both, each bind-mounted (not a
    named Docker volume) to `./virtuoso-data/{current,history}` so
    `virtuoso.ini` and the data/log files sit together on the host,
    directly accessible without `docker volume inspect`.
  - `GRAPHDB_HOST`/`GRAPHDB_USER`/`GRAPHDB_PASS`/`GRAPHDB_DBNAME`/
    `GRAPHDB_HISTORY` are replaced by `VIRTUOSO_HOST`/`VIRTUOSO_USER`/
    `VIRTUOSO_PASS`/`VIRTUOSO_HISTORY_HOST` (no dbname concept needed -
    each Virtuoso instance's endpoint is a distinct host:port instead).
  - New `lib/virtuoso_update_client.rb` (`CBGP::VirtuosoUpdateClient`):
    Virtuoso's SPARQL Update endpoint (`/sparql-auth`) requires HTTP
    Digest auth and rejects Basic outright (confirmed live; no
    `virtuoso.ini` setting in this build offers a way around it), and the
    `sparql-client` gem has no Digest support - this class covers exactly
    the write path with a small Digest handshake, exposing the same
    `#update`/`#insert_data` shape `DATABASE_UPDATE`/
    `HISTORY_DATABASE_UPDATE` already had. Reads are untouched: plain
    `SPARQL::Client` against Virtuoso's unauthenticated `/sparql` endpoint,
    same as before.
  - Added `net-http-digest_auth` as a dependency.
  - Dropped the `onto:` (Ontotext/GraphDB) SPARQL prefix, declared in every
    query but never actually used in any query body.
- `docs/source/installation.md`/`configuration.md` rewritten for the
  Virtuoso setup (no repository-creation step needed at all now - each
  container already is a store). `docker-compose-graphdb.yml` kept as a
  reference/rollback point for the retired GraphDB setup, not maintained
  going forward. `docs/source/backup_and_migration.md` still describes the
  old GraphDB backup procedure - flagged prominently as stale pending a
  Virtuoso-specific rewrite, rather than left looking authoritative.

## [0.15.0] - 2026-08-17
### Added
- `publication_cbgp_authors` ontology field: an ORCID cross-reference to
  `member` (mirrors `project_pi_orcid`'s `references`/`references-via`/
  `references-label` shape), so publications can finally identify which
  authors are CBGP personnel the same way projects identify their PI.
- `lib/doi_registration_agency.rb`: resolves a DOI's registration agency
  (DataCite/Crossref/etc.) via `doi.org/doiRA/`, ported (not taken on as a
  gem dependency) from `fair_champion_harvester`'s
  `DOI.resolve_doi_to_registration_agency`, used by Community-FAIR-Tests.
- `lib/crossref_parser.rb`: a direct `api.crossref.org` parser, so
  Crossref-registered DOIs no longer have to go via OpenAIRE's aggregation.
- `lib/personnel_matcher.rb`: matches a publication's parsed authors against
  existing `member` records - by exact ORCID, or otherwise by an exact,
  accent-insensitive given+family name match - and records confirmed
  matches' ORCIDs on `publication_cbgp_authors`. Deliberately exact-only,
  never fuzzy: a false positive would misattribute an outside co-author's
  identity to a CBGP member, which is worse than an occasional missed match.
### Changed
- `lib/loaders.rb`'s DOI loader now resolves the registration agency first
  and dispatches straight to `datacite_parser`/`crossref_parser`, falling
  back to `openaire_parser` only when the agency is unknown or the
  preferred parser comes back empty - instead of always trying DataCite
  first and blindly retrying on any error.
### Fixed
- `datacite_parser`/`openaire_parser` parsed each author's ORCID and then
  discarded it, keeping only the bare name string - the ORCID is now
  returned alongside the dataset so it can feed personnel matching.
- `datacite_parser`'s HTTP retry loop retried up to 5 times immediately
  with no backoff on *any* `StandardError`, including permanent failures
  like a bad DOI; capped at 2 attempts.
- `openaire_parser` shadowed its own `doi:` parameter with a re-extraction
  loop that unconditionally raised `TypeError` on real OpenAIRE responses
  (`Array#[]` called with a String key) - removed; the already-known input
  DOI is used directly, like `datacite_parser`/`crossref_parser` already do.
- `openaire_parser`'s `journal`/`title` extraction was missing the `.first`
  its sibling parsers use, so it stored literal `["Journal of Things"]`-style
  bracketed strings instead of the plain value.
### Removed
- `lib/params_parsers.rb`: dead code left over from before the
  `Dataset`/ontology-driven refactor - referenced a `CBGP::Publication`/
  `CBGP::Publication::Author` class pair that no longer exists, and ontology
  field IDs (`newpub2_*`) that only exist in a `_BACKUP2` ontology snapshot,
  not the live one. Nothing in the app called any method in this file.

## [0.14.1] - 2026-07-30
### Added
- A live, working example of `local:has-defaults` in the ontology:
  `project_test_default_field`, a disposable sandbox field (visible, not
  hidden this time) that pre-fills with different text on the Research
  vs. Personnel Project forms. `local:has-defaults` lost its only real
  example when `project_category` was removed in 0.13.0, leaving the
  mechanism entirely undemonstrated in the ontology.
### Fixed
- `docs/source/data_model.md`'s "Worked example" section covered
  `local:requires-field` and `local:has-formulas` but had **zero**
  example of `local:has-defaults` itself, despite that being the section
  the surrounding prose introduced - flagged directly by the user.
  Rewritten (English + Spanish) to walk through all three per-form
  mechanisms with accurate, distinct real fields for each. Also fixed a
  subtler inaccuracy caught in the same pass: the old `has-formulas`
  example queried `project_annual_income` as if it were the calculated
  field, when it's actually the *input* to the real calculated field
  (`project_cbgp_overheads`).

## [0.14.0] - 2026-07-30
### Changed
- Reworked the add/edit form layout to be significantly more compact.
  Root causes fixed rather than papered over:
  - `.question-label`'s left-aligned, zero-margin styling was scoped only
    to the Publications form; every other form's labels fell through to a
    generic centered `H1-H4` rule and the browser's default `<h4>` margin,
    compounding with `.field-row`'s own spacing into rows roughly 3x taller
    than intended. Un-scoped so every form gets the same compact treatment.
  - `_section.erb`/`_questionnaire.erb` padded every section and the end
    of the whole form with seven stacked `<br>` tags - removed; row
    spacing already comes from `.field-row` itself.
  - Removed a dead jsTree CDN theme stylesheet loaded on every page for a
    library nothing in this app actually uses (the tree-select widget is
    fully hand-rolled) - also removed an empty leftover `<style>` block.
### Fixed
- **Data loss bug**: `_textfield.erb`/`_field.erb`/`_smallfield.erb` (the
  widgets behind `honorific_title`, `project_application_reference`,
  `project_call_for_proposal`, `project_end_date_extension`,
  `project_partner_institutions`) rendered an always-empty box regardless
  of the field's actual stored value. Saving *any* edit to a record with
  one of these fields already filled in silently wiped it, since the
  blank-looking box submitted as blank. Fixed by actually displaying the
  current value; the field now correctly round-trips through an edit.
  Found live, root-caused, and fixed in the same session.
- `honorific_title` was mistakenly declared `Multiple`-cardinality in the
  ontology (CBGP-Ontology) even though the widget only ever supported one
  value - corrected to `Single`, matching actual behavior.

## [0.13.1] - 2026-07-29
### Added
- `docs/source/data_model.md` (English + Spanish): a new architecture-
  reference page explaining the two-layer shape every record actually has
  on disk (graph-level metadata - `dcterms:created`/`dcterms:modified`/
  `dcterms:type` - versus the SIO reified-attribute content inside the
  named graph itself), how both connect back to the ontology's Forms/
  Sections/Questions/Answers classes, and worked SPARQL examples for
  writing a raw query against the triple store directly - including the
  non-obvious two-hop indirection `local:has-formulas` and
  `local:has-defaults` both use (Form → an intermediate node → the actual
  field), contrasted with `local:requires-field`'s direct link. Linked
  from [Philosophy & Design](philosophy.md) and the main table of
  contents.

## [0.13.0] - 2026-07-29
### Added
- Every record, on every form, now automatically gets `dcterms:type
  <form-class-uri>` written onto its graph at save time
  (`write_dataset_to_db_query`), stamped from the true form (not the
  shared dbname) - a real Dublin Core term ("the nature or genre of the
  resource"), in the same default-graph provenance slot as the existing
  `dcterms:created`/`dcterms:modified` triples. Display label resolves for
  free from the form class's own existing bilingual `rdfs:label` - no new
  answer-block or ontology configuration needed for this to work on any
  current or future form.
### Removed
- `project_category`, the hand-declared hidden discriminator field
  (shipped in 0.11.0) distinguishing Research vs Personnel Project
  records, is gone - it was deployment-specific and only ever needed as a
  form discriminator, a need the new universal `dcterms:type` stamp
  covers generically for every form, not just these two. Its question
  class, answer-block, both answers, and both `local:has-defaults` nodes
  were removed from the ontology; existing sandbox records were migrated
  by a one-off backfill utility (`utilities/backfill_dcterms_type.rb`).
### Fixed
- The calculated field's live-preview JavaScript only ever worked when a
  calculated field happened to render (by `local:question-order`) after
  every field it depends on - otherwise its dependency-listener setup ran
  before the dependency's own input existed in the DOM and silently never
  attached. Fixed by deferring listener attachment to `DOMContentLoaded`.
- `HiddenField` questions (e.g. the now-removed `project_category`) still
  rendered a label and an empty row on the add/edit form. Now fully
  suppressed in add/edit mode; search mode is unaffected (still the
  filterable dropdown added in 0.12.0).
- Found while investigating the above: `local:has-defaults` is only ever
  applied to a brand-new record (via `new_with_defaults`) - never
  re-applied on edit, so a record that started without a default-derived
  value keeps missing it forever, even across edits. No code change (the
  new `dcterms:type` stamp is unconditional on every write and isn't
  affected by this), but worth documenting as a general gotcha for any
  future use of `local:has-defaults`.

## [0.12.0] - 2026-07-28
### Added
- **Calculated fields**: a form can now declare that one of its fields is
  computed automatically from other field values, rather than typed in by
  the user, via a new `local:has-formulas` ontology branch (Dentaku
  expressions - a safe, sandboxed expression evaluator, not Ruby `eval`).
  Like `local:has-defaults`/`local:requires-field`, this is declared
  per-form: the same shared field can be calculated differently on two
  different forms, or not calculated at all on a form that doesn't declare
  a formula for it.
  - Computation is server-side and authoritative, always run at save time
    from that submission's other field values - nothing a user could type
    or tamper with in a calculated field's own widget (which carries no
    `name` attribute at all) ever reaches the database.
  - **Dependency chains are supported**: one calculated field's formula can
    reference another calculated field's result (e.g. a percentage
    calculated *of* another percentage, rather than of a raw input
    field), resolved automatically via a bounded fixed-point iteration -
    no need to declare fields in dependency order.
  - The widget (`_calculated.erb`) shows a greyed-out, read-only box with
    the formula displayed underneath in plain text, plus a live
    (non-authoritative) preview that recomputes as dependency fields
    change and cascades correctly through a dependency chain.
  - Demonstrated on the Research/Personnel Project forms' `project_overheads`
    ("UPM overheads") / `project_cbgp_overheads` fields (a real two-step
    chain), plus a disposable `project_test_*` sandbox chain for manual
    testing - all percentages are explicitly-marked placeholders pending
    real confirmation from CBGP/UPM administration.
  - Documented (English + Spanish) in the Admin Guide's new "Calculated
    fields" section, including the per-form declaration requirement for
    ontology editors.
### Fixed
- `GET /cbgp/search-dataset/:database` 500'd for any form containing a
  `HiddenField`-widget question (e.g. `project_category`, shipped in
  0.11.0) because no `_search_hiddenfield.erb` partial existed. Added one:
  since a HiddenField is still a genuine controlled-vocabulary field even
  though it's invisible on the add/edit form, search mode now renders it
  as an ordinary dropdown, letting records be filtered by that value.

## [0.11.0] - 2026-07-28
### Added
- Support for multiple ontology **Forms sharing one dbname/graph table**:
  Research Project (`cbgp:project`) and Personnel Project
  (`cbgp:personnel_project`) are now two distinct forms over the same
  `project` table, each showing only its own relevant subset of the shared
  question classes. The Personnel Project field list is a placeholder for
  now, pending curation from the Admin team - this feature exists precisely
  so that curation can happen entirely in the ontology, with no code changes
  required, once they decide what they actually need.
- **Per-form default answers**: a form can now declare a default value for
  one of its fields via a new `local:has-defaults` branch pointing at
  `pre-populated-answer` nodes (`local:default-for-field` +
  `local:default-value`), so the same shared question class can default
  differently depending on which form is used. Used to build a hidden,
  multilingual `project_category` discriminator field (defaults to
  "Research Project" / "Personnel Project" depending on which form created
  the record), so records can be queried by project type without exposing
  the field to the user.
- **Per-form required fields**: a form can now mark one of its fields
  mandatory via a new `local:requires-field` annotation, direct from the
  form class to the question class (no reification needed, unlike
  defaults, since "required" carries no value of its own). Enforced
  server-side before anything is written to the database, reusing the
  existing friendly-error/`ValidationError` machinery, and surfaced to
  users as a bold red asterisk next to the field label on the form.
- `HiddenField`, an existing but previously-unused ontology widget type, is
  now exercised for the first time by the `project_category` field above.
### Fixed
- `GET /cbgp/dataset/:database` (and the equivalent user-facing route) built
  the add/edit questionnaire from the record's shared dbname instead of its
  specific form class, so two forms sharing one dbname would incorrectly
  both render whichever form's fields happened to match the dbname string.
  The admin `POST /cbgp/validate-dataset/:database` route had the same bug
  on the validation-error redisplay path. Both are fixed by threading the
  true form class through as a hidden `form_class` field on submission,
  since the URL alone only ever carries the shared dbname.
- Added `code10`, `consejo`, `genero`, and `cluster` to the members XML
  export (`xmlmembers.erb`), which were missing from the exported fields.

## [0.10.0] - 2026-07-09
### Added
- Full bilingual (English/Spanish) end-user documentation site, built from
  scratch with Sphinx + MyST + sphinx-intl, hosted on Read the Docs
  (`docs/source/`): Philosophy & Design (the ontology-driven/metaprogrammed
  architecture, its novelty relative to Rails/Django scaffolding, CEDAR,
  VIVO, Wikibase, and SHACL+DASH), Installation, Configuration, a five-page
  Admin Guide (data entry, history & snapshots, search & queries, cross-
  references, exports), a User Guide, and a Time Travel / API guide covering
  the history query endpoints shipped in 0.9.0 with real worked examples.
  Every page ships with a complete Spanish translation via `.po` catalogs
  under `docs/source/locale/es/`.
- `docs/source/backup_and_migration.md` (EN+ES): what actually needs backing
  up (only the `cbgp-graphdb` Docker volume and `.env` — everything else is
  reproducible), a self-alerting nightly backup script that captures both a
  native GraphDB backup and a vendor-neutral N-Quads dump of every
  repository (portable to any RDF store, not just GraphDB) and emails an
  alert on failure using the application's own `NOTIFY_*` SMTP settings,
  disaster-recovery restore, and full server-migration steps.
- `.env.example` — a safe, checked-in placeholder template for every `.env`
  variable the application reads, previously undocumented in the repo.
### Fixed
- `docker-compose.yml` was missing several `.env` variables
  (`configuration.rb` aborts startup without them: `NOTIFY_PW`,
  `CBGP_USERS`, `CBGP_SECRET`, `NOTIFY_TO`, `NOTIFY_UN`, `GRAPHDB_DBNAME`,
  `GRAPHDB_HISTORY`) and had a malformed `CBGP_KB` value with a stray
  trailing `#"`. Found while writing the installation documentation, since
  following it as written would otherwise have failed.

## [0.9.0] - 2026-07-09
### Added
- SCD Type 2 history query layer ("time machine"), built on the recording
  mechanism shipped in 0.7.0: `lib/history_queries.rb` provides schema-agnostic
  primitives (never assume a past snapshot's shape matches today's ontology)
  composed into two queries — a record's complete version history resolved by
  an identifying field (e.g. a member's full history by ORCiD, from creation
  to now), and a facet/date-range filtered search across every record of a
  type that's durable across deletions (a deleted record still contributes
  via its last known snapshot, with an optional numeric field summed across
  the matches). Every result is a real `RDF::Repository` (each contributing
  snapshot kept in its own named graph, so same-named fields across different
  versions never collide) served as JSON-LD or TriG.
- Three new read-only API endpoints exposing the above over HTTP, so any
  language/tool can call them directly (not just this app's own views):
  `POST /cbgp/query-history/:database` (duplicates `query-dataset`'s request
  shape — arbitrary facet/date-range params, optional `sum_field` — against
  history instead of current state), `GET /cbgp/history/:database/:questionclass/:value`
  (one record's timeline), and `GET /cbgp/facets/:form_type` (exposes the
  field/controlled-vocabulary metadata already used to render forms, for
  building external query UIs without scraping HTML).
- `utilities/time_machine.rb` CLI (`history`/`funding` subcommands) as a
  quick way to exercise the above without the web app.
### Fixed
- `escape_for_literal` (used to sanitize every field value before writing it
  into a SPARQL string literal) never actually escaped backslashes — its
  `gsub('\\', '\\\\')` was silently a no-op (gsub re-interprets backslash
  sequences in a *string* replacement, so the "doubled" backslash collapsed
  back to a single one). A value containing a literal backslash could produce
  a malformed SPARQL literal and fail to save. Fixed with the block form of
  `gsub`, which isn't subject to that re-interpretation.
### Testing
- New `spec/lib/history_queries_spec.rb` (50 examples) and
  `spec/lib/escape_for_literal_spec.rb` (6 examples, including a real
  round-trip through `RDF::Turtle::Reader`) — full suite now 128 examples.

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

[Unreleased]: https://github.com/CBGP-UPM-INIA-PUBLIC/CBGP-Databases/compare/v0.9.0...HEAD
[0.9.0]: https://github.com/CBGP-UPM-INIA-PUBLIC/CBGP-Databases/compare/v0.8.2...v0.9.0
[0.8.2]: https://github.com/CBGP-UPM-INIA-PUBLIC/CBGP-Databases/compare/v0.8.1...v0.8.2
[0.8.1]: https://github.com/CBGP-UPM-INIA-PUBLIC/CBGP-Databases/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/CBGP-UPM-INIA-PUBLIC/CBGP-Databases/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/CBGP-UPM-INIA-PUBLIC/CBGP-Databases/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/CBGP-UPM-INIA-PUBLIC/CBGP-Databases/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/CBGP-UPM-INIA-PUBLIC/CBGP-Databases/commits/main
