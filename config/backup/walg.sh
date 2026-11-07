#!/usr/bin/env bash
# Continuous backup of the database with WAL-G, run on the database server's host by cron
# (docs/RUNBOOK.md §2). Postgres itself ships every WAL segment as it's finished (archive_command);
# this script takes the daily base backups that replay starts from, and checks it all works.
#
#   walg.sh base    daily: a full base backup (and, if WALG_RETAIN_FULL is set, deletes older ones)
#   walg.sh check   every 15 minutes: archiving is configured, not failing, not backed up, and the
#                   newest base backup is under a day old; pings WALG_HEARTBEAT_URL on success and
#                   its /fail address with the reason otherwise
#   walg.sh list    the base backups in the store
#
# Settings come from /etc/hardpoint/backup.env (or the environment):
#   WALG_HEARTBEAT_URL   e.g. a healthchecks.io check expecting a ping every 15 minutes
#   WALG_RETAIN_FULL     keep this many base backups (needs a key that may delete; otherwise leave
#                        it unset and let the bucket's lifecycle rules expire old objects)
#   DB_CONTAINER         default hardpoint-db
#   MAX_BASE_BACKUP_AGE_HOURS  default 26;  MAX_READY_WAL  default 100 (segments waiting to ship)
set -Eeuo pipefail

[ -f /etc/hardpoint/backup.env ] && set -a && . /etc/hardpoint/backup.env && set +a

DB_CONTAINER=${DB_CONTAINER:-hardpoint-db}
MAX_BASE_BACKUP_AGE_HOURS=${MAX_BASE_BACKUP_AGE_HOURS:-26}
MAX_READY_WAL=${MAX_READY_WAL:-100}

log() { echo "$(date -u +%FT%TZ) walg: $*"; }
in_db() { docker exec -i -u postgres "$DB_CONTAINER" "$@"; }
walg() { in_db bash /usr/local/bin/hardpoint-wal-g "$@"; }
sql() { in_db psql -U postgres -d postgres -Atq -v ON_ERROR_STOP=1 -c "$1"; }

ping_heartbeat() { # "" for success, or a failure reason
  [ -n "${WALG_HEARTBEAT_URL:-}" ] || return 0
  if [ -z "$1" ]; then
    curl -fsS -m 10 --retry 3 "$WALG_HEARTBEAT_URL" > /dev/null || true
  else
    curl -fsS -m 10 --retry 3 --data-raw "$1" "${WALG_HEARTBEAT_URL%/}/fail" > /dev/null || true
  fi
}

fail() { log "FAILED: $*"; ping_heartbeat "$*"; exit 1; }

base() {
  log "base backup starting"
  # shellcheck disable=SC2016 # $PGDATA is the container's
  in_db bash -c 'bash /usr/local/bin/hardpoint-wal-g backup-push "$PGDATA"' || fail "base backup failed"
  log "base backup done"
  if [ -n "${WALG_RETAIN_FULL:-}" ]; then
    walg delete retain FULL "$WALG_RETAIN_FULL" --confirm || fail "couldn't delete old base backups"
  fi
  check
}

check() {
  in_db test -r /etc/wal-g/env -a -x /opt/wal-g/wal-g \
    || fail "WAL-G isn't configured in $DB_CONTAINER (run config/backup/install_walg.sh and fill in /etc/hardpoint/wal-g/env)"
  [ "$(sql "SHOW archive_mode")" = "on" ] || fail "archive_mode is off (restart the db accessory after deploying postgresql.conf)"

  local failing
  failing=$(sql "SELECT coalesce(last_failed_time > coalesce(last_archived_time, '-infinity'), false) || ' ' || coalesce(last_failed_wal, '-') FROM pg_stat_archiver")
  [ "${failing%% *}" = "false" ] || fail "archiving is failing (last failed WAL ${failing#* }); see bin/kamal accessory logs db"

  local ready
  ready=$(sql "SELECT count(*) FROM pg_ls_archive_statusdir() WHERE name LIKE '%.ready'")
  [ "$ready" -le "$MAX_READY_WAL" ] || fail "$ready WAL segments are waiting to be archived"

  local newest age_hours
  newest=$(walg backup-list 2>/dev/null | awk 'NR > 1 && NF >= 2 { modified = $2 } END { print modified }')
  [ -n "$newest" ] || fail "there's no base backup yet (run walg.sh base)"
  age_hours=$(( ( $(date -u +%s) - $(date -u -d "$newest" +%s) ) / 3600 ))
  [ "$age_hours" -lt "$MAX_BASE_BACKUP_AGE_HOURS" ] || fail "the newest base backup is ${age_hours} hours old"

  log "ok: archiving healthy ($ready waiting), newest base backup $newest"
  ping_heartbeat ""
}

trap 'fail "walg.sh ${1:-} stopped unexpectedly at line $LINENO"' ERR

case "${1:-}" in
  base) base ;;
  check) check ;;
  list) walg backup-list --detail ;;
  *) echo "usage: $0 base|check|list" >&2; exit 64 ;;
esac
