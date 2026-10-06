#!/bin/bash
# Portable (vendor-neutral) export and import of a Virtuoso store as N-Quads.
#
#   utilities/virtuoso_nquads.sh export <container> <dba-password> <destination-dir>
#   utilities/virtuoso_nquads.sh import <container> <dba-password> <source-dir>
#
# export  writes every graph of the store in <container> as gzipped N-Quads
#         files into a new dated folder under <destination-dir> and prints its
#         path. N-Quads is a plain-text W3C standard that any triple store can
#         read, unlike Virtuoso's own backup files - this is the insurance
#         against that format ever becoming a problem.
# import  loads such files (*.nq, *.nq.gz) into the store in <container>. It
#         ADDS to whatever is there, so import into a new, empty store (see
#         docs: Backup & Migration).
#
# <container> is the Docker container name (see `docker ps`; with Docker
# Compose's defaults cbgp-databases-virtuoso-current-1 and
# cbgp-databases-virtuoso-history-1). Do the current and history stores one
# after the other, each with its own password. Run it on the server itself;
# the user needs access to Docker. The dump procedure is OpenLink's own, in
# utilities/virtuoso_dump_nquads.sql.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SQL="$HERE/virtuoso_dump_nquads.sql"
DEFAULT_GRAPH="urn:cbgp:nquads-import"   # only used for a statement that has no graph of its own
STAMP=$(date '+%Y-%m-%d-%H-%M-%S')

usage() { sed -n '2,/^set -uo/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//' >&2; exit 2; }
[ $# -eq 4 ] || usage
MODE="$1"; CONTAINER="$2"; PASS="$3"; DIR="$4"

isql_exec() { docker exec "$CONTAINER" isql 1111 dba "$PASS" exec="$1" 2>&1; }
fail() { echo "ERROR: $*" >&2; exit 1; }

docker exec "$CONTAINER" true 2>/dev/null || fail "cannot reach container '$CONTAINER' - is it running? (docker ps)"

case "$MODE" in
  export)
    [ -f "$SQL" ] || fail "missing $SQL"
    WORK="nq-${STAMP}"                          # relative to the store's data directory
    DEST="${DIR%/}/${STAMP}"
    # Install (or replace) the dump procedure in this store.
    out=$(docker exec -i "$CONTAINER" isql 1111 dba "$PASS" < "$SQL" 2>&1)
    grep -q 'Error' <<<"$out" && fail "could not create the dump procedure: $(grep -m1 Error <<<"$out")"
    # The server runs as the 'virtuoso' user, so the folder must belong to it.
    docker exec -u virtuoso "$CONTAINER" mkdir -p "/database/${WORK}" || fail "cannot create a working folder in the container"
    out=$(isql_exec "dump_nquads('${WORK}', 1, 100000000, 1);")
    if ! grep -q 'Done' <<<"$out" || grep -q 'Error' <<<"$out"; then
      docker exec "$CONTAINER" rm -rf "/database/${WORK}"
      fail "the dump failed: $(grep -m1 -E 'Error' <<<"$out")"
    fi
    mkdir -p "$DIR" && docker cp "${CONTAINER}:/database/${WORK}" "$DEST" || fail "could not copy the dump out of the container"
    docker exec "$CONTAINER" rm -rf "/database/${WORK}"          # do not leave a copy filling the store's volume
    find "$DEST" -name '*.nq*' -size +0 | grep -q . || fail "no non-empty N-Quads file in $DEST"
    echo "$DEST"
    ;;

  import)
    compgen -G "${DIR%/}/*.nq" >/dev/null || compgen -G "${DIR%/}/*.nq.gz" >/dev/null || fail "no *.nq or *.nq.gz files in $DIR"
    WORK="nq-import-${STAMP}"                   # a new folder name each time, so the loader never skips it as 'already loaded'
    docker exec -u virtuoso "$CONTAINER" mkdir -p "/database/${WORK}" || fail "cannot create a working folder in the container"
    docker cp "${DIR%/}/." "${CONTAINER}:/database/${WORK}/" || fail "could not copy the files into the container"
    docker exec "$CONTAINER" chown -R virtuoso:virtuoso "/database/${WORK}"      # docker cp leaves them owned by root
    out=$(isql_exec "ld_dir('${WORK}', '*.nq*', '${DEFAULT_GRAPH}'); rdf_loader_run(); checkpoint;")
    grep -q 'Error' <<<"$out" && fail "the load failed: $(grep -m1 Error <<<"$out")"
    # Every queued file must now be loaded (state 2) with no error.
    bad=$(isql_exec "select count(*) from DB.DBA.LOAD_LIST where ll_file like '${WORK}/%' and (ll_state <> 2 or ll_error is not null);" | grep -E '^[0-9]+$' | head -1)
    total=$(isql_exec "select count(*) from DB.DBA.LOAD_LIST where ll_file like '${WORK}/%';" | grep -E '^[0-9]+$' | head -1)
    isql_exec "delete from DB.DBA.LOAD_LIST where ll_file like '${WORK}/%';" >/dev/null
    docker exec "$CONTAINER" rm -rf "/database/${WORK}"
    [ "${total:-0}" -gt 0 ] || fail "the loader found no files to load"
    [ "${bad:-1}" -eq 0 ] || fail "${bad} of ${total} files did not load cleanly (select ll_file, ll_state, ll_error from DB.DBA.LOAD_LIST)"
    echo "loaded ${total} file(s) into ${CONTAINER}"
    ;;

  *) usage ;;
esac
