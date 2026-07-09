# Notebooks

Drop finished `.ipynb` files here (e.g. `member_history_example.ipynb`,
`funding_aggregate_example.ipynb`). These get bundled into an embedded
**JupyterLite** instance — a real, live Jupyter environment that runs
entirely in the reader's browser (Pyodide/WASM), no install and no command
line required. A reader just clicks a button on the docs page and gets a
running notebook they can execute cell-by-cell. This was chosen deliberately
over the more common `nbsphinx` approach (which only shows static,
already-run output) because the people this is for can't run a notebook
from a command line.

To add one:

1. Write and test the notebook however you like (Jupyter Notebook, Jupyter
   Lab, VS Code, etc.) using Python — JupyterLite's in-browser kernel is
   Python via Pyodide, so the notebook needs to use `requests`/`fetch`-style
   HTTP calls against the `/cbgp/query-history/...`, `/cbgp/history/...`,
   and `/cbgp/facets/...` endpoints described in `../time_travel.md`, not a
   Ruby kernel.
2. Save the finished `.ipynb` file into this directory.
3. Reference it from `../time_travel.md` with the `jupyterlite` directive,
   e.g.:
   ```
   {jupyterlite} member_history_example.ipynb
   :width: 100%
   :height: 600px
   ```
   (as a real MyST directive on that page — the `conf.py` comment near
   `jupyterlite_contents` shows the exact fenced form.)
4. Rebuild the docs (`docs/README.md` has the command) — the first build
   with real notebooks present will take noticeably longer, since Sphinx
   has to assemble the JupyterLite site itself; that's normal.

This file itself (`README.md`) is excluded from the build (see
`exclude_patterns` in `conf.py`) so it won't show up as a stray page.
