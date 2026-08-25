# Screenshot shot list

Not part of the built site — a running checklist of every screenshot
referenced from the docs, so they're all in one place to capture. Each entry
below corresponds to a real `![...](...)` image reference already in the
docs source, pointing at a file that doesn't exist yet (so it'll show as a
broken image locally/on RTD until you add it — that's expected and
intentional, not a bug).

Save screenshots into `docs/source/_static/screenshots/` using the exact
filename listed, then the existing `![]()` reference in that page will just
start working — no other changes needed.

| Filename | Used on page | What it should show |
|---|---|---|
| `docker-compose-up.png` | installation.md | A terminal showing `docker compose up -d` completing successfully with all three containers started/healthy |
| `admin-dashboard.png` | admin/data_entry.md | The admin dashboard showing the list of record types |
| `admin-add-form.png` | admin/data_entry.md | An add/edit form showing a mix of field types (text, dropdown, currency, a cross-reference lookup) |
| `admin-validation-error.png` | admin/data_entry.md | A form redisplayed after a validation error, showing the error banner |
| `admin-search-form.png` | admin/search_and_queries.md | A search screen showing a mix of field types, and a results list below it |
| `admin-xref-typeahead.png` | admin/cross_references.md | A cross-reference field mid-search, showing the dropdown of matching suggestions as text is typed |
| `admin-export-link.png` | admin/exports.md | A search results table with the "Download to Excel" link visible above it |
| `user-dashboard.png` | user_guide.md | The User dashboard after logging in, showing the record types available for submission |
| `user-submission-form.png` | user_guide.md | A User submission form, showing its (smaller) set of fields |
| `user-thank-you.png` | user_guide.md | The confirmation screen shown after a successful submission |
