# Backup & Migration

This page is for whoever manages the server this application runs on —
not the day-to-day database Admin role described in the
[Admin Guide](admin/index.md), but whoever is responsible for Docker,
backups, and (eventually) moving this to a different machine. It assumes
comfort with a command line, unlike the rest of this site.

```{note}
Read this page **before** you need it. The single most common way to
lose a research institute's data permanently is discovering, during an
emergency server migration, that nobody backed up the database — this
page exists so that never happens here.
```

## What actually needs backing up

Almost everything about this application is disposable and can be
recreated from scratch: the Docker images are pulled fresh from a
registry, the code is this Git repository, and the ontology that drives
every form and field is fetched live from the network every time it's
needed (see [Philosophy & Design](philosophy.md)). None of that is
unique to this server, and none of it needs backing up.

**Exactly two things are not disposable:**

1. **The GraphDB data** — the current-state and history repositories
   described in [Installation](installation.md#the-two-repository-database).
   This is the institute's actual data: every record, and (per
   [History & Snapshots](admin/history_and_snapshots.md)) every past
   version of every record. It lives in the `cbgp-graphdb` Docker
   volume, entirely separate from the application's own containers or
   code — deleting or recreating the containers doesn't touch it, but
   losing that volume with no backup means losing the data permanently,
   with no way to reconstruct it from anything else on this list.
2. **The `.env` file** — not data, but the credentials and settings
   needed to bring the application back up (see
   [Configuration](configuration.md)). It's deliberately excluded from
   Git, so it exists in exactly one place unless someone has copied it
   somewhere safe.

```{note}
Running `docker compose up -d` on a brand-new machine, using nothing but
a fresh checkout of this Git repository, will start a **completely
empty** database — the Docker image contains the application, not the
institute's data. If the `cbgp-graphdb` volume doesn't come along too
(by restoring a backup, per this page), every record is simply gone.
```

## Making a backup

### The native GraphDB backup

GraphDB has a built-in backup mechanism, reachable over the same
connection as its Workbench — run these commands on the server itself
(or over SSH into it), not from a remote laptop, since GraphDB's port is
only published to the server's own loopback address
(`127.0.0.1:7200` in `docker-compose.yml`):

```bash
curl -f -X POST -OJ 'http://localhost:7200/rest/recovery/backup'
```

This creates a single file (named automatically, like
`backup-2026-07-09-14-30-00.tar`) containing **every repository** in this
GraphDB instance — both the current-state and history databases — in one
atomic operation, without needing to stop GraphDB or interrupt anyone
using the application. If GraphDB's own security is enabled (see
[Configuration](configuration.md#graphdb-connection)), add credentials:

```bash
curl -f -X POST -OJ -u "$GRAPHDB_USER:$GRAPHDB_PASS" \
  'http://localhost:7200/rest/recovery/backup'
```

```{note}
The `-f` flag matters: without it, curl treats an HTTP error response
from GraphDB (for example, GraphDB not being up yet) as "success" and
happily saves the error page as if it were a real backup file — a
silent failure that looks exactly like a working backup until the day
someone actually needs it. `-f` makes curl fail loudly instead.
```

```{note}
By default this backup does **not** include GraphDB's own user accounts
(a separate thing from this application's `CBGP_USERS` — see
[Configuration](configuration.md#login-accounts)) — only the actual
data. If GraphDB security is enabled, note down the GraphDB
username/password separately (e.g. wherever `.env` is stored), since
restoring this backup elsewhere won't recreate that account for you.
```

### A vendor-neutral quads dump

The native backup above is fast to create and restore, but it's tied to
GraphDB — restoring it requires another GraphDB instance, of a
compatible version. As a second, independent safety net, it's worth also
exporting the raw data in an open, W3C-standard RDF format that **any**
triplestore can read — not just GraphDB, but Virtuoso, Fuseki, or
whatever the institute might use in the future, if it ever needed to:

```bash
curl -f -H 'Accept: text/x-nquads' \
  "http://localhost:7200/repositories/${GRAPHDB_DBNAME}/statements?infer=false" \
  -o "${GRAPHDB_DBNAME}.nq"

curl -f -H 'Accept: text/x-nquads' \
  "http://localhost:7200/repositories/${GRAPHDB_HISTORY}/statements?infer=false" \
  -o "${GRAPHDB_HISTORY}.nq"
```

(`$GRAPHDB_DBNAME`/`$GRAPHDB_HISTORY` are the same repository IDs from
[Configuration](configuration.md#graphdb-connection) — one dump per
repository, since they're two separate GraphDB repositories, not two
graphs inside one.) Each command produces a single N-Quads file — a
plain-text, line-per-triple format that preserves which named graph
every triple belongs to (important for this application, since the
history mechanism depends on that — see
[History & Snapshots](admin/history_and_snapshots.md)) and that virtually
every RDF tool in existence can read. Add `-u "$GRAPHDB_USER:$GRAPHDB_PASS"`
to either command if GraphDB security is enabled, the same as above.

```{note}
This isn't a replacement for the native backup — restoring from N-Quads
means creating fresh repositories and re-importing the data, which is
slower and loses GraphDB-specific repository settings. Think of it as
insurance against the native backup format itself becoming a
problem someday (an incompatible future GraphDB version, or moving away
from GraphDB entirely), not as the primary way to recover from an
ordinary failure — that's what the section above is for.
```

Move the resulting files — both the `.tar` backup and the `.nq` quad
dumps — somewhere **other than this server** — external storage, another
machine, cloud storage, whatever the institute already uses for backups
generally. A backup that only exists on the same machine it's protecting
against isn't a real backup.

## Scheduling automatic backups

Rather than remembering to run the commands above by hand, have `cron`
do it on a schedule. This wrapper script does both the native GraphDB
backup and the vendor-neutral quads dump every night, checks that each
one actually succeeded (not just that curl didn't crash), emails an
alert if anything went wrong, and only cleans up old files once it
knows tonight's backups are good — so a failure is something you find
out about the next morning, not the day of an actual disaster:

```bash
#!/bin/bash
# /opt/cbgp-databases/backup.sh
set -uo pipefail

ENV_FILE="/opt/cbgp-databases/.env"   # wherever this deployment's .env actually lives
BACKUP_DIR="/var/backups/cbgp-databases"
mkdir -p "$BACKUP_DIR"

# Load GRAPHDB_DBNAME/GRAPHDB_HISTORY/NOTIFY_* from .env.
set -a
source "$ENV_FILE"
set +a

STAMP=$(date '+%Y-%m-%d-%H-%M-%S')
FAILED=0

# Emails NOTIFY_TO using the exact same SMTP server/credentials the
# application itself already sends mail through (see Configuration's
# "Admin email notifications") - no extra mail software needed beyond
# curl, which this script already requires.
alert_failure() {
  local reason="$1"
  printf 'From: %s\nTo: %s\nSubject: [CBGP] Backup problem on %s - %s\n\n%s\n' \
    "$NOTIFY_FROM" "$NOTIFY_TO" "$(hostname)" "$(date '+%Y-%m-%d %H:%M')" "$reason" \
    > /tmp/cbgp-backup-alert.txt
  curl -s --ssl-reqd "smtp://${NOTIFY_SMTP_ADDRESS}:${NOTIFY_SMTP_PORT}" \
    --mail-from "$NOTIFY_FROM" --mail-rcpt "$NOTIFY_TO" \
    --upload-file /tmp/cbgp-backup-alert.txt \
    --user "${NOTIFY_UN}:${NOTIFY_PW}"
  rm -f /tmp/cbgp-backup-alert.txt
}

cd "$BACKUP_DIR"

# 1) Native GraphDB backup - the fast, primary way to recover.
curl -sS -f -X POST -OJ 'http://localhost:7200/rest/recovery/backup'
if [ $? -ne 0 ]; then
  alert_failure "The native GraphDB backup request failed - GraphDB may be down or unreachable."
  FAILED=1
else
  LATEST_TAR=$(ls -t "$BACKUP_DIR"/*.tar 2>/dev/null | head -n1)
  if [ -z "$LATEST_TAR" ] || [ ! -s "$LATEST_TAR" ]; then
    alert_failure "The native GraphDB backup reported success but no non-empty .tar file was found."
    FAILED=1
  fi
fi

# 2) Vendor-neutral quads dump of both repositories - insurance against
# the native backup format itself becoming a problem someday.
for REPO in "$GRAPHDB_DBNAME" "$GRAPHDB_HISTORY"; do
  OUT="$BACKUP_DIR/${REPO}-${STAMP}.nq"
  curl -sS -f -H 'Accept: text/x-nquads' \
    "http://localhost:7200/repositories/${REPO}/statements?infer=false" \
    -o "$OUT"
  if [ $? -ne 0 ] || [ ! -s "$OUT" ]; then
    alert_failure "The quads dump of repository '${REPO}' failed or produced an empty file."
    FAILED=1
  fi
done

# Only prune old files once today's backups (of both kinds) are confirmed good.
if [ "$FAILED" -eq 0 ]; then
  find "$BACKUP_DIR" -name '*.tar' -mtime +14 -delete
  find "$BACKUP_DIR" -name '*.nq' -mtime +14 -delete
fi

exit "$FAILED"
```

```{note}
If GraphDB security is enabled, add `-u "$GRAPHDB_USER:$GRAPHDB_PASS"`
to both `curl` calls that talk to GraphDB (the backup request and the
two quad-dump requests), the same as the manual commands above.
```

Make it executable (`chmod +x /opt/cbgp-databases/backup.sh`), then add
it to the server's crontab (`crontab -e`) to run every night at 2 AM:

```
0 2 * * * /opt/cbgp-databases/backup.sh >> /var/log/cbgp-backup.log 2>&1
```

```{note}
Why nightly, and not more often? Records in this application are
transcribed from paper originals that continue to exist independently
(see [Data Entry](admin/data_entry.md)) — so the worst case if a disaster
strikes right before the next backup is losing a handful of hours' worth
of *re-entry* work, not losing the underlying information itself. Given
how infrequently data actually changes here (this system is used on an
hourly basis, not a minute-by-minute one), nightly backups are already
generous, not a compromise. If this application is ever used for data
that has no paper (or other) backstop, that calculus changes and a
tighter schedule would be worth revisiting.
```

```{note}
This only protects against database corruption or accidental deletion —
backups written to `/var/backups` on the **same server** are lost right
along with everything else if that server itself is lost or
decommissioned. Periodically copy `$BACKUP_DIR` somewhere physically
separate (`rsync`/`scp` to another machine, a cloud storage bucket,
whatever the institute already trusts for offsite backups) — a cron job
that only ever writes to local disk gives a false sense of security.
```

## Restoring from a backup (disaster recovery)

This is for when something has gone wrong on the **same** server — an
accidental bulk deletion, a corrupted repository, a failed upgrade — and
the goal is to put a known-good backup back in place, not to move to
different hardware (that's the next section).

1. **Stop the application** (not GraphDB itself) so nobody can write new
   data while the restore is in progress:
   ```bash
   docker compose stop cbgp-databases
   ```
2. **Find the backup to restore** — the most recent `.tar` file in
   `$BACKUP_DIR` (or wherever backups were copied off-server to, if the
   problem is severe enough that local backups are also suspect).
3. **Restore it**, telling GraphDB to replace whatever is currently in
   each repository rather than erroring out because they already exist:
   ```bash
   curl -X POST 'http://localhost:7200/rest/recovery/restore' \
     -F 'params={"removeStaleRepositories": true};type=application/json' \
     -F file=@./backup-2026-07-09-14-30-00.tar
   ```
   (substitute the real filename). `removeStaleRepositories: true` is
   the important difference from a migration restore — it tells GraphDB
   this is a deliberate overwrite of existing, currently-broken
   repositories, not a mistake.
4. **Restart the application** and confirm the data looks right — check
   a few familiar records via [Search & Queries](admin/search_and_queries.md)
   before considering the incident resolved:
   ```bash
   docker compose start cbgp-databases
   ```

```{note}
Restoring a backup rolls the **entire** GraphDB instance back to exactly
how it was at backup time — both repositories, current state and
history alike. Anything written after that backup was taken (any
record added, edited, or deleted since) is lost, not merged with the
restored data. This is why the backup schedule in the previous section
matters: the most recent backup is the most that can ever be recovered.
```

## Migrating to a new server

This is the procedure for moving the whole application — and, critically,
**all of its data** — from one machine to another (for example, because
the current server is being decommissioned).

1. **On the old server**, make a fresh backup right before migrating
   (see "Making a backup" above), so it reflects the most current data,
   not last night's cron run.
2. **Copy two files to the new server**: the backup `.tar` file, and the
   `.env` file (transfer `.env` carefully — it contains real passwords;
   `scp` over SSH is fine, email or chat is not).
3. **On the new server**, install Docker, check out this repository, and
   create the empty volume exactly as in
   [Installation](installation.md#running-via-docker):
   ```bash
   docker volume create cbgp-graphdb
   ```
4. **Start GraphDB only** (not the full application yet), using
   `docker-compose-graphdb.yml` as described in
   [Installation](installation.md#running-via-docker):
   ```bash
   docker compose -f docker-compose-graphdb.yml up -d
   ```
   Unlike a normal fresh install, **do not** create the two repositories
   by hand this time — restoring the backup recreates them automatically,
   with their original IDs and settings intact.
5. **Restore the backup** into this brand-new, still-empty GraphDB
   instance:
   ```bash
   curl -X POST 'http://localhost:7200/rest/recovery/restore' \
     -F 'params={};type=application/json' \
     -F file=@./backup-2026-07-09-14-30-00.tar
   ```
   (substitute the real backup filename). This recreates both
   repositories with all their data — current state and full history —
   exactly as they were on the old server, so the existing
   `GRAPHDB_DBNAME`/`GRAPHDB_HISTORY` values already in the copied
   `.env` continue to match with no changes needed.
6. **If GraphDB security was enabled on the old server**, recreate the
   same GraphDB user account on the new instance (Workbench →
   **Setup → Users**) with the same username/password already in
   `GRAPHDB_USER`/`GRAPHDB_PASS`, since (per the note above) the backup
   didn't include that account.
7. **Start the full application** and confirm the data is really there:
   ```bash
   docker compose up -d
   ```
   Log in and check that familiar records appear in a search (see
   [Search & Queries](admin/search_and_queries.md)) before treating the
   old server as safe to decommission.

```{note}
A tempting shortcut is to skip all of the above and just copy the
`cbgp-graphdb` Docker volume's files directly (stop GraphDB, `tar` up
the volume's data directory, move it, extract it into a fresh volume on
the new machine). This can work, but only if both servers run the exact
same GraphDB version, and it requires stopping GraphDB for the entire
copy (no "while the application stays up" option, unlike the
backup/restore approach above). The REST API method in this page is the one
GraphDB's own vendor documents, tests, and supports — prefer it unless
there's a specific reason not to.
```
