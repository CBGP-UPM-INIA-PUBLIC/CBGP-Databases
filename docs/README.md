# Documentation — maintainer notes

Not part of the built site (excluded via `conf.py`'s `exclude_patterns`) —
this is for whoever is editing the docs themselves.

## Building locally

```bash
# One-time setup (uses the conda Python on this machine, not system python3)
/home/osboxes/Miniconda/bin/python3 -m pip install -r docs/requirements.txt

# Build
/home/osboxes/Miniconda/bin/python3 -m sphinx -b html docs/source docs/build/html

# Open docs/build/html/index.html in a browser
```

Re-run the build command after every edit — Sphinx is fast and does
incremental builds. Warnings about broken image references to files under
`_static/screenshots/` that don't exist yet are expected (see
`SCREENSHOTS.md`); any other warning or error should be fixed before
considering a page done.

## Adding a screenshot

1. Find the `![alt text](../_static/screenshots/some-name.png)` reference
   already in the relevant page (every screenshot the docs need already has
   a placeholder reference — nothing to add on the Markdown side).
2. Save your image as `docs/source/_static/screenshots/some-name.png`
   (exact filename from the reference).
3. Rebuild — the broken-image warning goes away and the real image renders.
4. Cross it off the table in `docs/SCREENSHOTS.md`.

## Updating the Spanish translation

Translatable strings live in `docs/source/locale/es/LC_MESSAGES/*.po`, one
file per source page, kept in sync with the English source via
[sphinx-intl](https://github.com/sphinx-doc/sphinx-intl). After editing any
English page:

```bash
PY=/home/osboxes/Miniconda/bin/python3

# 1. Re-extract translatable strings from the English source into .pot templates
$PY -m sphinx -b gettext docs/source docs/build/gettext

# 2. Merge the updated .pot templates into the existing Spanish .po files -
#    unchanged strings are left alone, new strings appear untranslated,
#    strings whose English source changed are marked "fuzzy" (needs review)
$PY -m sphinx_intl update -p docs/build/gettext -d docs/source/locale -l es

# 3. Translate: open docs/source/locale/es/LC_MESSAGES/<page>.po in any .po
#    editor (Poedit, or a plain text editor) and fill in msgstr for every
#    empty or "fuzzy" msgid.

# 4. Build the Spanish version locally to check it
$PY -m sphinx -b html -D language=es docs/source docs/build/html-es
```

Read the Docs itself never runs step 1/2 for you — those only happen when
someone runs this locally and commits the updated `.po` files. RTD just
builds whatever `.po` files are already committed, once for each linked
language project (see the "Connecting to Read the Docs" section below).

## Adding a Jupyter notebook

See `docs/source/notebooks/README.md`.

## Connecting to Read the Docs (one-time, do this once there's real content worth previewing)

Read the Docs' multi-language support is **one project per language**,
linked together as "Translations" of a parent — this is what produces the
language switcher in the flyout menu. This all happens on readthedocs.org
with your account; nothing more to do in the repo once `.readthedocs.yaml`
exists (it already does).

1. Go to <https://readthedocs.org> and sign in (or create an account) with
   your GitHub login, so it can see this repository.
2. **Import the English (parent) project**: "Add project" → pick this repo
   → leave the default project slug/name → its default language is English,
   which matches `language = 'en'` in `conf.py`. This becomes the parent.
3. **Import the same repo again as the Spanish project**: "Add project" →
   pick this repo again → RTD will ask you to change the slug (e.g.
   `cbgp-databases-es`) since the English one already took the default →
   in that new project's **Admin → Settings → Language**, set it to
   **Spanish**.
4. **Link them**: in the *English (parent)* project's **Admin →
   Translations**, add the Spanish project you just created.
5. Trigger a build on both projects (Builds → Build Version). Once both
   succeed, the English project's docs page shows a language flag/switcher
   in the bottom-right flyout menu — that's the "click the box" toggle.

If a build fails, the RTD build log is the place to look first — usually
either a missing dependency (check `docs/requirements.txt`) or a Sphinx
warning being treated as an error.
