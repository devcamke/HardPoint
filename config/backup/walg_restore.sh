#!/usr/bin/env bash
# Point-in-time restore from WAL-G (docs/RUNBOOK.md §3): fetches a base backup into an EMPTY data
# directory and sets Postgres up to replay the archived WAL after it, up to a moment you choose
# (or to the end of the archive), then open for business on a new timeline.
#
#   walg_restore.sh DATA_ROOT                                  # as late as the archive goes
#   walg_restore.sh DATA_ROOT --time "2026-11-07 14:32:00+03"  # just before something went wrong
#   walg_restore.sh DATA_ROOT --backup base_000000010000000A000000F2 --time "..."
#   walg_restore.sh DATA_ROOT --drill ...   # a rehearsal: the copy never archives into the store
#
# DATA_ROOT is the host directory the db accessory mounts at /var/lib/postgresql (its `data`
# directory, e.g. /root/hardpoint-db/data); Postgres 18's data goes in DATA_ROOT/18/docker. Stop
# the accessory first and move the old data aside (or restore into a new directory to try it out).
# WAL-G runs in a throwaway postgres:18 container with the same mounts as the accessory, so it
# needs install_walg.sh's /opt/hardpoint/wal-g and /etc/hardpoint/wal-g on this host.
set -euo pipefail

usage() { echo "usage: $0 DATA_ROOT [--time 'YYYY-MM-DD HH:MM:SS+TZ'] [--backup NAME|LATEST] [--drill]" >&2; exit 64; }
DATA_ROOT=${1:-}; [ -n "$DATA_ROOT" ] || usage; shift
TARGET_TIME="" BACKUP=LATEST DRILL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --time) TARGET_TIME=${2:?}; shift 2 ;;
    --backup) BACKUP=${2:?}; shift 2 ;;
    --drill) DRILL=1; shift ;;
    *) usage ;;
  esac
done

PG_IMAGE=${PG_IMAGE:-postgres:18}
PG_UID=${PG_UID:-999} # the postgres user in the official image
PGDATA_SUBDIR=${PGDATA_SUBDIR:-18/docker}
WRAPPER=${WRAPPER:-$(cd "$(dirname "$0")" && pwd)/wal-g.sh} # config/postgres/wal-g.sh, installed beside this script
# How to run WAL-G with DATA_ROOT at /var/lib/postgresql. Overridable to rehearse without Docker.
WALG=${WALG:-"docker run --rm --user $PG_UID:$PG_UID -v $DATA_ROOT:/var/lib/postgresql -v /opt/hardpoint/wal-g:/opt/wal-g:ro -v /etc/hardpoint/wal-g:/etc/wal-g:ro -v $WRAPPER:/usr/local/bin/hardpoint-wal-g:ro $PG_IMAGE bash /usr/local/bin/hardpoint-wal-g"}
CONTAINER_PGDATA=${CONTAINER_PGDATA:-/var/lib/postgresql/$PGDATA_SUBDIR}
RESTORE_COMMAND=${RESTORE_COMMAND:-"bash /usr/local/bin/hardpoint-wal-g wal-fetch %f %p"}

log() { echo "$(date -u +%FT%TZ) walg-restore: $*"; }
pgdata="$DATA_ROOT/$PGDATA_SUBDIR"

if [ -d "$pgdata" ] && [ -n "$(ls -A "$pgdata")" ]; then
  log "$pgdata isn't empty: stop the db accessory and move it aside first"; exit 1
fi
[ -f "$WRAPPER" ] || { log "can't find $WRAPPER (install config/postgres/wal-g.sh beside this script)"; exit 1; }
install -d -m 700 "$pgdata"
chown -R "$PG_UID:$PG_UID" "$DATA_ROOT" 2>/dev/null || true

log "fetching base backup $BACKUP"
$WALG backup-fetch "$CONTAINER_PGDATA" "$BACKUP"
# A fetch that was interrupted can still exit 0; a complete one has these.
for f in PG_VERSION backup_label global/pg_control; do
  [ -s "$pgdata/$f" ] || { log "the fetch is incomplete ($f missing); empty $pgdata and run again"; exit 1; }
done

# Replay the archive, then become a normal primary. These settings sit in postgresql.auto.conf
# until reset (the runbook's last step); recovery.signal is removed by Postgres when it's done.
{
  echo "# Added by walg_restore.sh $(date -u +%FT%TZ)"
  echo "restore_command = '$RESTORE_COMMAND'"
  if [ -n "$TARGET_TIME" ]; then echo "recovery_target_time = '$TARGET_TIME'"; fi
  echo "recovery_target_action = 'promote'"
  # A rehearsal must not push its new timeline into production's archive.
  if [ -n "$DRILL" ]; then echo "archive_mode = off"; fi
} >> "$pgdata/postgresql.auto.conf"
touch "$pgdata/recovery.signal"
chown -R "$PG_UID:$PG_UID" "$pgdata" 2>/dev/null || true
chmod 700 "$pgdata"

log "ready: start Postgres (bin/kamal accessory boot db). It replays WAL${TARGET_TIME:+ up to $TARGET_TIME}, then opens."
log "afterwards: ALTER SYSTEM RESET restore_command; ALTER SYSTEM RESET recovery_target_time; ALTER SYSTEM RESET recovery_target_action; then walg.sh base"
