# Configuration file for the Sphinx documentation builder.
# https://www.sphinx-doc.org/en/master/usage/configuration.html

project = 'CBGP-Databases'
copyright = '2026, CBGP-UPM-INIA'
author = 'CBGP-UPM-INIA'

# Kept in sync manually with the repo's own VERSION file - see
# ../installation.md for what this number means (Docker tag, etc.).
release = '0.9.0'
version = '0.9.0'

extensions = [
    'myst_parser',
    'sphinx_copybutton',
    'jupyterlite_sphinx',
]

templates_path = ['_templates']
exclude_patterns = ['_build', 'Thumbs.db', '.DS_Store', 'notebooks/README.md']

source_suffix = {
    '.md': 'markdown',
    '.rst': 'restructuredtext',
}

root_doc = 'index'

myst_enable_extensions = [
    'colon_fence',   # ::: fenced directives, nicer than eval-rst for admonitions
    'deflist',
    'substitution',
]

# Auto-generates #anchor-slugs for headings up to this depth, so in-page
# links like [Running via Docker](#running-via-docker) resolve. Off by
# default in MyST.
myst_heading_anchors = 3

# --- HTML output -------------------------------------------------------

html_theme = 'sphinx_rtd_theme'
html_static_path = ['_static']

# --- Internationalization (EN source, ES translation via sphinx-intl) --
#
# Repo-side setup only: extracting translatable strings into locale/ and
# translating the resulting .po files. Actually *serving* both languages
# with the flyout language switcher is configured on readthedocs.org itself
# (one RTD project per language, linked as "Translations" of a parent) - see
# ../README.md for the exact steps. Do not try to replicate that here.
language = 'en'
locale_dirs = ['locale/']
gettext_compact = False  # one .po file per source page, not one big catalog
gettext_uuid = True      # stable message IDs across re-extractions

# --- jupyterlite-sphinx (in-browser, click-and-run notebooks) ----------
#
# Chosen over nbsphinx (which only embeds static pre-run output) because
# the intended readers can't run a notebook from a command line - this
# embeds a real, live JupyterLite (Pyodide/WASM) instance that runs
# entirely in the reader's browser with no install. Notebooks placed under
# notebooks/ (see notebooks/README.md) are bundled into the JupyterLite
# build; time_travel.md embeds a specific one with, e.g.:
#   {jupyterlite} member_history_example.ipynb
#   :width: 100%
#   :height: 600px
# (as a real ``` -fenced MyST directive on that page, not a Python comment)
# No notebooks exist yet - the user adds them.
jupyterlite_contents = ['notebooks']
