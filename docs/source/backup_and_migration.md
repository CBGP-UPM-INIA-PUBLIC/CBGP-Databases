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

```{note}
Before 2026-08-25 this application used GraphDB, and this page described its
backup procedure. It was rewritten for Virtuoso on 2026-10-06, and **every
command below was run for real** against the two Virtuoso stores of a working
installation: each backup was restored into a fresh, empty directory and the
restored store was compared with the original (an exact match, not just a
similar size). Virtuoso's version at the time was 7.2.18; if you run a much
newer image, repeat the restore test described in [Checking that a backup
really works](#checking-that-a-backup-really-works) before relying on it.
```

## What actually needs backing up

Almost everything about this application is disposable and can be
recreated from scratch: the Docker images are pulled fresh from a
registry, the code is this Git repository, and the ontology that drives
every form and field is fetched live from the network every time it's
needed (see [Philosophy & Design](philosophy.md)). None of that is
unique to this server, and none of it needs backing up.

**Exactly two things are not disposable:**

1. **The two Virtuoso stores** — the current-state store and the history
   store described in [Installation](installation.md#the-two-store-database).
   This is the institute's actual data: every record, and (per
   [History & Snapshots](admin/history_and_snapshots.md)) every past
   version of every record. They live in the two directories
   `virtuoso-data/current` and `virtuoso-data/history` next to
   `docker-compose.yml`, entirely separate from the application's own
   container or code — deleting or recreating containers doesn't touch
   them, but losing those directories with no backup means losing the data
   permanently, with no way to reconstruct it from anything else on this
   list. **Both** need backing up: the history store is the only copy of
   every earlier version.
2. **The `.env` file** — not data, but the credentials and settings
   needed to bring the application back up (see
   [Configuration](configuration.md)). It's deliberately excluded from
   Git, so it exists in exactly one place unless someone has copied it
   somewhere safe. It also holds the password each store was created with,
   and a restored store keeps *that* password (see [Restoring from a
   backup](#restoring-from-a-backup-disaster-recovery)).

```{note}
Running `docker compose up -d` on a brand-new machine, using nothing but
a fresh checkout of this Git repository, will start **completely
empty** stores — the Docker image contains the application, not the
institute's data. If the data directories don't come along too (by
restoring a backup, per this page), every record is simply gone.
```

## Making a backup

There are two ways, and they complement each other: an **online backup**
(the stores keep running; this is what the nightly job below uses) and a
**cold copy** (a brief shutdown, but the simplest thing to reason about —
best right before an upgrade or a move).

### An online backup

Virtuoso has a built-in online backup that writes a consistent copy while
the store keeps serving requests, so nobody using the application notices.
Run these on the server itself (or over SSH into it) — the stores' ports are
only published to the server's own loopback address (see
`docker-compose.yml`). `docker ps` shows the container names; with Docker
Compose's defaults they are `cbgp-databases-virtuoso-current-1` and
`cbgp-databases-virtuoso-history-1`. The password is the store's `dba`
password from `.env` (`VIRTUOSO_PASS`, and `HISTORY_PASS` if you set one —
see [Configuration](configuration.md#virtuoso-connection)).

```bash
# 1. a directory for the backup INSIDE the store's data directory.
#    It must belong to the 'virtuoso' user, which the server runs as.
docker exec -u virtuoso cbgp-databases-virtuoso-current-1 mkdir -p /database/backup-today

# 2. take a complete backup into it
docker exec cbgp-databases-virtuoso-current-1 isql 1111 dba "$VIRTUOSO_PASS" \
  exec="backup_context_clear(); backup_online('current_', 1000000, 0, vector('backup-today'));"

# 3. copy it out of the container, then remove the working copy
docker cp cbgp-databases-virtuoso-current-1:/database/backup-today ./backup-current
docker exec cbgp-databases-virtuoso-current-1 rm -rf /database/backup-today
```

Success looks like two lines ending `Done.` and no `Error`; the result is a
single file, `current_1.bp` (several megabytes for the institute's real data
at the time of writing — a complete backup of both stores took about nine
seconds). Repeat with the history container, `HISTORY_PASS` and the prefix
`history_` for the second store.

Three details are easy to get wrong:

- **The directory is relative, not absolute.** `vector('backup-today')`
  works; `vector('/database/backup-today')` is refused with *"Access … is
  denied due to access control in ini file"*, because Virtuoso only writes
  where its configuration (`DirsAllowed`) allows, and it reads paths
  relative to its own data directory.
- **`backup_context_clear()` matters.** Without it, every backup after the
  first contains only what *changed* since the previous one, and restoring
  needs the whole chain of files. Clearing first makes each backup complete
  on its own, which is what you want for a backup you may need to use years
  from now.
- **Use `docker cp` to copy it out, not an ordinary `cp`.** The files belong
  to the container's internal user and are readable by it alone, so as your
  normal user you cannot read them straight from `virtuoso-data/`.

```{note}
`isql` takes the password on its command line, so for the moment it runs the
password is visible to anyone who can list processes on the server. On a
server only trusted administrators log in to, that is acceptable; the
scheduled script below does the same.
```

### A cold copy

The other way is to stop the stores, copy their data directories, and start
them again. It needs a short outage (the application is unavailable while the
stores are stopped), but a copy of a stopped store is exactly the store, with
nothing to go wrong in the middle:

```bash
cd /path/to/CBGP-Databases                  # the directory with docker-compose.yml
docker compose stop -t 60 cbgp-databases virtuoso-current virtuoso-history
sudo cp -a virtuoso-data /var/backups/cbgp-databases/cold-$(date +%F)
docker compose start virtuoso-current virtuoso-history cbgp-databases
```

`-t 60` gives each store up to a minute to shut down cleanly and write its
final checkpoint — the default ten seconds is not always enough for a large
store. `sudo` is needed because the files belong to the container's internal
user. **Never copy the directories while the stores are running:** the copy
may catch the database file half-written and be unusable.

A cold copy also contains the stores' own settings (`virtuoso.ini`), which an
online backup does not.

### A portable N-Quads export

Virtuoso's own backup files can only be restored by Virtuoso. As insurance
against that format ever becoming a problem, the repository includes
`utilities/virtuoso_nquads.sh`, which writes a whole store out as
**N-Quads** — a plain-text W3C standard that any triple store can read — and
loads such files back in. It keeps every record's own named graph, which this
application's history mechanism depends on (see [History &
Snapshots](admin/history_and_snapshots.md)).

```bash
cd /path/to/CBGP-Databases
set -a; source .env; set +a                        # for VIRTUOSO_PASS / HISTORY_PASS

utilities/virtuoso_nquads.sh export cbgp-databases-virtuoso-current-1 "$VIRTUOSO_PASS" /var/backups/cbgp-databases/nquads/current
utilities/virtuoso_nquads.sh export cbgp-databases-virtuoso-history-1 "${HISTORY_PASS:-$VIRTUOSO_PASS}" /var/backups/cbgp-databases/nquads/history
```

Each command prints the new dated folder it wrote, holding gzipped
`output000001.nq.gz` files (one per roughly 100 MB of data). For the
institute's real data at the time of writing, each store came to well under a
megabyte compressed and took a few seconds, while the store kept running.

Virtuoso does not ship a dump command ready-made. The script installs the
procedure OpenLink Software publishes for this purpose
([source](https://vos.openlinksw.com/owiki/wiki/VOS/VirtRDFDumpNQuad), kept in
`utilities/virtuoso_dump_nquads.sql`) into the store the first time it runs;
that stored procedure is the only change it makes to the store, and running it
again simply replaces it.

To load an export — into a **new, empty store**, since importing *adds* to
whatever is already there:

```bash
utilities/virtuoso_nquads.sh import cbgp-databases-virtuoso-current-1 "$VIRTUOSO_PASS" /var/backups/cbgp-databases/nquads/current/2026-10-06-03-00-00
```

It copies the files into the container, loads them with Virtuoso's bulk
loader, checks that every file loaded without error, and cleans up after
itself. Loading the same files twice does not duplicate anything.

How far to trust it: the real current and history stores were each exported
and imported into a brand-new store, and a checksum over every statement of all
of the application's graphs matched exactly (about 62,000 and 49,000
statements). Things to know:

- A new Virtuoso store already contains a handful of standard vocabulary
  graphs (OWL and similar) that an export includes too. Importing re-adds
  them, and because some of their statements use blank nodes, a few
  statements in those built-in graphs end up duplicated. They are not the
  institute's data and nothing depends on them.
- It restores **data only**: not `virtuoso.ini`, and not the `dba` password,
  which is whatever the new store was created with — `.env` must match it.
- It is slower and cruder than a native backup, so think of it as a second,
  independent copy to keep alongside the nightly backups, not a replacement
  for them. Run it, say, weekly (see the next section).

### Checking that a backup really works

A backup you have never restored is a hope, not a backup. Once, and again
after upgrading Virtuoso, restore one into a scratch directory and compare it
with the live store, following [Restoring from a
backup](#restoring-from-a-backup-disaster-recovery) but into a directory of
your own and a container of your own on a different port, never over the real
one. The simplest comparison is the total number of triples — the same query
on both stores should agree:

```sparql
SELECT (COUNT(*) AS ?triples) WHERE { GRAPH ?g { ?s ?p ?o } }
```

(Run it at `http://localhost:18890/sparql` and `…:18891/sparql` for the
current and history stores, and on your scratch container's own port.) The
counts match only if nothing was written between taking the backup and
asking, so check on a quiet moment.

Move the resulting backups — the `.bp` files, the cold copy or the N-Quads files — somewhere
**other than this server**: external storage, another machine, cloud
storage, whatever the institute already uses for backups generally. A backup
that only exists on the same machine it's protecting against isn't a real
backup.

## Scheduling automatic backups

Rather than remembering to run the commands above by hand, have `cron`
do it on a schedule. This wrapper script takes an online backup of both
stores every night, checks that each one actually succeeded (not just that
the command didn't crash), emails an alert if anything went wrong, and only
cleans up old backups once it knows tonight's are good — so a failure is
something you find out about the next morning, not the day of an actual
disaster:

```bash
#!/bin/bash
# /opt/cbgp-databases/backup.sh
set -uo pipefail

ENV_FILE="/opt/cbgp-databases/.env"          # wherever this deployment's .env actually lives
BACKUP_DIR="/var/backups/cbgp-databases"
KEEP_DAYS=14
# Docker Compose's default container names; override if yours differ (docker ps).
CURRENT_CONTAINER="${CURRENT_CONTAINER:-cbgp-databases-virtuoso-current-1}"
HISTORY_CONTAINER="${HISTORY_CONTAINER:-cbgp-databases-virtuoso-history-1}"

# Load VIRTUOSO_PASS / HISTORY_PASS / NOTIFY_* from .env.
set -a
source "$ENV_FILE"
set +a
CURRENT_PASS="$VIRTUOSO_PASS"
HISTORY_PASS_EFFECTIVE="${HISTORY_PASS:-$VIRTUOSO_PASS}"   # same fallback the application uses

STAMP=$(date '+%Y-%m-%d-%H-%M-%S')
FAILED=0

# Emails NOTIFY_TO using the same SMTP server/credentials the application
# itself already sends mail through (see Configuration's "Admin email
# notifications") - no extra mail software needed beyond curl.
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

# backup_store <container> <label> <dba password>
# Takes a full online backup (the store keeps running), copies it out of the
# container, and checks that a non-empty backup file really arrived.
backup_store() {
  local container="$1" label="$2" pass="$3"
  local dir="backup-${STAMP}"          # relative to the store's data directory
  local dest="${BACKUP_DIR}/${label}/${STAMP}"

  # The server runs as the 'virtuoso' user, so the directory must belong to it.
  if ! docker exec -u virtuoso "$container" mkdir -p "/database/${dir}" 2>/dev/null; then
    alert_failure "Could not reach the ${label} Virtuoso container '${container}' - is it running?"
    return 1
  fi

  # backup_context_clear() makes every backup a complete, self-contained one
  # (otherwise each would only hold what changed since the previous backup).
  local out
  out=$(docker exec "$container" isql 1111 dba "$pass" \
    exec="backup_context_clear(); backup_online('${label}_', 1000000, 0, vector('${dir}'));" 2>&1)
  if ! grep -q 'Done' <<<"$out" || grep -q 'Error' <<<"$out"; then
    alert_failure "The ${label} online backup failed: $(grep -m1 -E 'Error|error' <<<"$out")"
    docker exec "$container" rm -rf "/database/${dir}"
    return 1
  fi

  mkdir -p "${BACKUP_DIR}/${label}"
  if ! docker cp "${container}:/database/${dir}" "$dest"; then
    alert_failure "Could not copy the ${label} backup out of the container."
    docker exec "$container" rm -rf "/database/${dir}"
    return 1
  fi
  docker exec "$container" rm -rf "/database/${dir}"      # don't leave copies filling the store's volume

  if ! find "$dest" -name '*.bp' -size +0 | grep -q .; then
    alert_failure "The ${label} backup finished but no non-empty backup file was found in ${dest}."
    return 1
  fi
}

backup_store "$CURRENT_CONTAINER" current "$CURRENT_PASS"         || FAILED=1
backup_store "$HISTORY_CONTAINER" history "$HISTORY_PASS_EFFECTIVE" || FAILED=1

# Only prune old backups once tonight's are confirmed good.
if [ "$FAILED" -eq 0 ]; then
  find "$BACKUP_DIR" -mindepth 2 -maxdepth 2 -type d -name '20??-*' -mtime +"$KEEP_DAYS" -exec rm -r {} +
fi

exit "$FAILED"
```

Make it executable (`chmod +x /opt/cbgp-databases/backup.sh`), then add
it to the server's crontab (`crontab -e`) to run every night at 2 AM:

```
0 2 * * * /opt/cbgp-databases/backup.sh >> /var/log/cbgp-backup.log 2>&1
```

The user the job runs as must be allowed to use Docker (root, or a member of
the `docker` group). Each night leaves one dated folder per store under
`$BACKUP_DIR` (`current/2026-10-06-02-00-00/current_1.bp`, and the same for
`history/`), and folders older than `KEEP_DAYS` are removed.

The N-Quads export can be scheduled the same way, less often — it is a second
copy, not the main one. A small script and a weekly cron line (Sunday, 3 AM):

```bash
#!/bin/bash
# /opt/cbgp-databases/nquads.sh
set -uo pipefail
set -a; source /opt/cbgp-databases/.env; set +a
TOOL=/opt/cbgp-databases/utilities/virtuoso_nquads.sh
OUT=/var/backups/cbgp-databases/nquads
$TOOL export cbgp-databases-virtuoso-current-1 "$VIRTUOSO_PASS" "$OUT/current" || exit 1
$TOOL export cbgp-databases-virtuoso-history-1 "${HISTORY_PASS:-$VIRTUOSO_PASS}" "$OUT/history" || exit 1
find "$OUT" -mindepth 2 -maxdepth 2 -type d -name '20??-*' -mtime +60 -exec rm -r {} +
```

```
0 3 * * 0 /opt/cbgp-databases/nquads.sh >> /var/log/cbgp-nquads.log 2>&1
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
accidental bulk deletion, a corrupted store, a failed upgrade — and the goal
is to put a known-good backup back in place, not to move to different
hardware (that's the next section). The steps below restore one store; for a
full recovery, do the current-state store and then the history store, from the
**same night's** backups, so the two stay in step with each other.

1. **Stop the application and the store being restored**, so nobody can
   write new data while the restore is in progress:
   ```bash
   cd /path/to/CBGP-Databases
   docker compose stop cbgp-databases virtuoso-current
   ```
2. **Set the damaged data aside** (don't delete it yet) and make an empty
   directory in its place, containing the store's settings and the backup:
   ```bash
   mv virtuoso-data/current virtuoso-data/current.damaged
   mkdir virtuoso-data/current
   sudo cp virtuoso-data/current.damaged/virtuoso.ini virtuoso-data/current/
   cp -r /var/backups/cbgp-databases/current/2026-10-06-02-00-00 virtuoso-data/current/backup
   ```
   (substitute the real dated folder; for an offsite copy, use whatever you
   copied it to.) If there is no `virtuoso.ini` to copy, see "[Getting a
   default `virtuoso.ini`](#a-default-virtuoso-ini)" below.
3. **Restore it.** This runs Virtuoso once, in a separate temporary container
   on the same image, to rebuild the database file from the backup. The
   directory it works in must contain *no* database file yet:
   ```bash
   docker run --rm -v "$PWD/virtuoso-data/current:/database" \
     openlink/virtuoso-opensource-7:latest \
     virtuoso-t +configfile virtuoso.ini +restore-backup current_ +backup-dirs backup
   ```
   The prefix after `+restore-backup` is the one the backup was made with
   (`current_`, or `history_` for the other store), *not* a path — the folder
   is given separately by `+backup-dirs`. It finishes with *"End of restoring
   from backup"* and a page count, and exits.
4. **Start the store and the application again**, and confirm the data looks
   right — check a few familiar records via [Search &
   Queries](admin/search_and_queries.md) before considering the incident
   resolved:
   ```bash
   docker compose start virtuoso-current cbgp-databases
   ```
   Starting hands the restored files back to the store's own user
   automatically.

```{note}
**The password comes back with the data.** A Virtuoso database stores its
`dba` password inside itself, so after a restore the store has the password it
had *when the backup was taken*, whatever `.env` or the `DBA_PASSWORD` setting
in `docker-compose.yml` now says (those are only used when a store is first
created). If you changed the password since the backup, the application will
be refused until `.env` is changed back to match.
```

```{note}
Restoring a backup rolls that **entire** store back to exactly how it was at
backup time. Anything written after that backup was taken (any record added,
edited, or deleted since) is lost, not merged with the restored data. This is
why the backup schedule in the previous section matters: the most recent
backup is the most that can ever be recovered. Keep `current.damaged` until
you are satisfied with the result; once you are, it can be deleted.
```

To restore from a **cold copy** instead, stop the stores, move the damaged
`virtuoso-data` aside, copy the cold copy back to `virtuoso-data` (with `sudo
cp -a`, to keep the ownership), and start them again — there is no restore
command, because the copy already *is* the stores.

To restore from an **N-Quads export**, start a new, empty store (an empty data
directory; Virtuoso creates it on first start) and import into it with
`utilities/virtuoso_nquads.sh import` as shown under [A portable N-Quads
export](#a-portable-n-quads-export). This is the slowest route, and the one to
use only if a native backup or cold copy is not available.

(a-default-virtuoso-ini)=
### Getting a default `virtuoso.ini`

A restore needs the store's configuration file but, unlike an online backup,
does not bring one with it. If you do not have the old one, let Virtuoso write
a default: start a throwaway container on a **separate scratch directory**
(never on the data directory you are about to restore into, because starting
a store also creates a database file there, and a restore needs none), stop
it, and copy just `virtuoso.ini` across:

```bash
mkdir /tmp/vt-scratch
docker run -d --name vt-scratch -e DBA_PASSWORD=scratch -v /tmp/vt-scratch:/database \
  openlink/virtuoso-opensource-7:latest
sleep 20 && docker rm -f vt-scratch
sudo cp /tmp/vt-scratch/virtuoso.ini virtuoso-data/current/
```

The default is the one the stores here were created with, so the restored
store behaves exactly as before.

## Migrating to a new server

This is the procedure for moving the whole application — and, critically,
**all of its data** — from one machine to another (for example, because
the current server is being decommissioned).

1. **On the old server**, make fresh backups right before migrating (see
   "Making a backup" above) so they reflect the most current data, not last
   night's cron run. A **cold copy** is the simplest choice for a move.
2. **Copy to the new server**: the backups (or the cold copy), and the `.env`
   file. Transfer `.env` carefully — it contains real passwords; `scp` over
   SSH is fine, email or chat is not.
3. **On the new server**, install Docker and check out this repository.
   Put `.env` in place, **before** the first `docker compose up` (the stores'
   passwords are set the first time each starts — see
   [Installation](installation.md#running-via-docker)).
4. **Put the data in place before starting anything:**
   - from a **cold copy**: copy it to be the repository's `virtuoso-data`
     directory (`sudo cp -a`); or
   - from **online backups**: do steps 2 and 3 of [Restoring from a
     backup](#restoring-from-a-backup-disaster-recovery) for each store, into
     fresh `virtuoso-data/current` and `virtuoso-data/history` directories
     (here you have no `virtuoso.ini` to copy; see "[Getting a default
     `virtuoso.ini`](#a-default-virtuoso-ini)" below).
5. **Start everything:**
   ```bash
   docker compose up -d
   ```
   Log in and check that familiar records appear in a search (see [Search &
   Queries](admin/search_and_queries.md)) before treating the old server as
   safe to decommission.

```{note}
Use the **same Virtuoso image** on both servers. `docker-compose.yml` asks for
`openlink/virtuoso-opensource-7:latest`, which can mean different versions on
different days; a data directory or backup made by one version is safe to open
with the same or a newer one, but not necessarily with an older one. Compare
`docker images` on both machines before the move, and pin the exact tag if
they differ.
```

## One-off data fixes

### Retyping dates stored as text

Since 2026-10-06 the application stores dates as real dates (`xsd:date`) and
refuses anything that isn't one (see [Data Model](data_model.md#how-values-are-typed)).
Every record saved **from then on** is typed correctly with no action on
your part. Records written before that — in particular a database loaded from
older data — hold their dates as text, and a date-range search against text
dates gives wrong answers without any error. They are converted once with a
script:

```bash
cd utilities
ruby retype_dates.rb --dry-run   # count what would change, change nothing
ruby retype_dates.rb             # do it
```

It reads the same `.env` as the application and works on **both** the current
repository and the history repository. Which fields are dates is read from the
ontology (every field whose widget is a date picker), not listed in the
script, so it follows whatever the ontology currently says. A value that is
not a full `YYYY-MM-DD` date is left untouched and reported, never guessed at.
It is safe to run again: values that are already dates are not matched. As
with any change to the whole database, take a [backup](#making-a-backup)
first.
