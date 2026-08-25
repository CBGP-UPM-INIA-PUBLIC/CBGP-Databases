# Installation

This page covers getting a working copy of the application running, end
to end: the two-store database it needs, the Docker images, and how
to choose a version. It assumes Docker is already installed on the machine
that will run this. Configuring *what the application does once it's
running* (the `.env` file) is the next page,
[Configuration](configuration.md) — do this page first, since the database
needs to exist before the application can start.

## The two-store database

This application stores data in [Virtuoso](https://vos.openlink.co.uk/),
a graph database, and it needs **two separate Virtuoso instances**, not one:

- A **current-state store** — every record as it exists right now.
  This is the one the application reads and writes for ordinary use.
- A **history store** — a permanent, append-only record of every
  prior version of every record, written automatically whenever something
  is edited or deleted. See
  [History & Snapshots](admin/history_and_snapshots.md) for what this
  means in practice; for installation purposes, it's enough to know it's a
  second, separate store that must exist before the application can
  start.

They're kept physically separate — two Virtuoso processes, not one process
with the history mixed in — specifically so that an ordinary search can
never accidentally turn up old, superseded data. This is also *why* it's
two whole Virtuoso instances rather than two repositories inside one, the
way the application's previous database (GraphDB) worked: a single
Virtuoso process is one graph store, with no separate-repository concept to
lean on instead.

```{note}
Before 2026-08-25 this application used GraphDB instead. The switch was
made because GraphDB's free/open tier returned to requiring periodic
license re-registration, which Virtuoso Open Source doesn't. If a
pre-2026-08-25 instance needs to keep running on GraphDB rather than
migrate, `docker-compose-graphdb.yml` in the repository still reflects
that setup, kept as a reference/rollback point rather than removed
outright — nothing in the running code depends on it, and it isn't
maintained going forward.
```

### No repository-creation step needed

Unlike GraphDB, Virtuoso doesn't ask for a one-time "create a repository"
step through a web console before it can be used — each Virtuoso container
*is* a store, ready to use the moment it starts. Standing up the two
containers (next section) is the entire setup step; there's nothing further
to click through.

## Running via Docker

The application ships as a Docker image; `docker-compose.yml` in this
repository runs all three containers together — the current-state Virtuoso,
the history Virtuoso, and the application itself:

```bash
docker compose up -d
```

Both Virtuoso containers are configured with **bind-mounted** host
directories (`./virtuoso-data/current` and `./virtuoso-data/history`,
created automatically on first start if they don't already exist) rather
than a named Docker volume — so each store's data files (`virtuoso.db`,
`virtuoso.log`, ...) *and* its configuration (`virtuoso.ini`) sit together
in one place directly on the host filesystem, easy to find without going
through `docker volume inspect`. One thing to know: those files are written
by the container's own internal user, not whichever user ran
`docker compose up`, so editing or deleting them by hand from the host
needs `sudo` (or another container mounting the same path) rather than
working as your normal user.

Each Virtuoso container's `dba` superuser password comes from `.env`
(`VIRTUOSO_PASS`/`HISTORY_PASS` — see [Configuration](configuration.md)),
so create `.env` with real values *before* the first `docker compose up`,
not after — the password is set the first time each container starts and
isn't automatically changed by editing `.env` later.

```{note}
Screenshot needed: `docs/source/_static/screenshots/docker-compose-up.png`
— a terminal showing `docker compose up -d` completing successfully with
all three containers reported as started/healthy.
```

![docker compose up succeeding](_static/screenshots/docker-compose-up.png)
*A successful `docker compose up -d`.*

## Choosing a version

The application's version number appears in three places that are always
kept in sync with each other in this repository: the `VERSION` file, the
image tag in `docker-compose.yml` (`markw/cbgp-databases:X.Y.Z`), and an
entry in `CHANGELOG.md` describing what changed in that release. There is
deliberately no `latest` tag in ordinary use — every release is a specific,
pinned version number, and upgrading is a deliberate choice (edit the tag
in `docker-compose.yml`, re-run `docker compose up -d`), not something that
happens automatically in the background.

To decide which version to run: read `CHANGELOG.md` in the repository from
the top down — each entry lists what was added, changed, or fixed in that
release — and pick the most recent one, or an earlier one specifically if
there's a reason to avoid a more recent change. `docker-compose.yml` as
checked into this repository already points at a specific known-good
version; there's no need to change it unless a newer release is wanted.

```{note}
This application is under active development, and its version numbering
follows a "we bump it and describe it every time something meaningful
ships" convention rather than a strict semantic-versioning contract — the
changelog entry is the reliable source of truth for what a given version
actually contains.
```
