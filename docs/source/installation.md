# Installation

This page covers getting a working copy of the application running, end
to end: the two-repository database it needs, the Docker images, and how
to choose a version. It assumes Docker is already installed on the machine
that will run this. Configuring *what the application does once it's
running* (the `.env` file) is the next page,
[Configuration](configuration.md) — do this page first, since the database
needs to exist before the application can start.

## The two-repository database

This application stores data in [GraphDB](https://www.ontotext.com/products/graphdb/),
a graph database, and it needs **two separate repositories inside the same
GraphDB instance**, not one:

- A **current-state repository** — every record as it exists right now.
  This is the one the application reads and writes for ordinary use.
- A **history repository** — a permanent, append-only record of every
  prior version of every record, written automatically whenever something
  is edited or deleted. See
  [History & Snapshots](admin/history_and_snapshots.md) for what this
  means in practice; for installation purposes, it's enough to know it's a
  second, separate repository that must exist before the application can
  start.

They're kept physically separate — two repositories, not one repository
with the history mixed in — specifically so that an ordinary search can
never accidentally turn up old, superseded data. Nothing about installing
or running the application differs between the two; GraphDB simply needs
both to exist, with names the application is told about
(see [Configuration](configuration.md)).

### Creating the two repositories

GraphDB itself doesn't come with these repositories pre-created — that's a
one-time setup step, done through GraphDB's own web interface (the
"Workbench"), not through this application:

1. Start GraphDB (see [Running via Docker](#running-via-docker) below) and
   open its Workbench in a browser — by default,
   `http://localhost:7200`.
2. Go to **Setup → Repositories → Create new repository**, choose the plain
   **GraphDB Repository** type (no reasoning/inference profile is needed;
   this application does its own querying), and give it an ID — this ID
   becomes the `GRAPHDB_DBNAME` value on the [Configuration](configuration.md)
   page. Repeat for the second repository, whose ID becomes `GRAPHDB_HISTORY`.
3. Leave the rest of the repository settings at their defaults unless
   there's a specific reason to change them.

```{note}
Screenshot needed: `docs/source/_static/screenshots/graphdb-create-repository.png`
— the GraphDB Workbench's "Create new repository" form, showing where the
repository ID is entered.
```

![GraphDB create-repository screen](_static/screenshots/graphdb-create-repository.png)
*The GraphDB Workbench's repository-creation screen.*

The two repository IDs are just names — they don't have to be any
particular value — but whatever they are, they need to match exactly what
gets written into `.env` as `GRAPHDB_DBNAME` and `GRAPHDB_HISTORY` on the
[Configuration](configuration.md) page. A mismatch here is the single most
common reason a freshly-installed instance fails to start or shows no data.

## Running via Docker

The application ships as a Docker image; this repository includes two
different Docker Compose files, for two different situations:

- **`docker-compose-graphdb.yml`** — GraphDB *only*, nothing else. Useful
  for the one-time repository-creation step above, or if GraphDB is meant
  to run somewhere separate from the application itself.
- **`docker-compose.yml`** — GraphDB *and* the application together, the
  normal way to run a complete instance.

Both expect a Docker volume named `cbgp-graphdb` to already exist (so
GraphDB's data survives container restarts/upgrades independently of the
containers themselves) — create it once, before the first start:

```bash
docker volume create cbgp-graphdb
```

Then, having created `.env` per the [Configuration](configuration.md) page
(the application container reads it via `env_file: .env` in
`docker-compose.yml`):

```bash
docker compose up -d
```

This starts GraphDB on `localhost:7200` (the Workbench) and the
application on `localhost:8000`. The very first time, GraphDB will be
empty — that's when you do the one-time repository-creation step above,
before the application can do anything useful.

```{note}
Screenshot needed: `docs/source/_static/screenshots/docker-compose-up.png`
— a terminal showing `docker compose up -d` completing successfully with
both containers reported as started/healthy.
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
