#!/bin/bash
# Runs WAL-G inside the Postgres container with its settings from /etc/wal-g/env (mounted from the
# host's /etc/hardpoint/wal-g; see docs/RUNBOOK.md §2). Postgres calls it for every finished WAL
# segment (archive_command in postgresql.conf), and config/backup/walg.sh for base backups.
#
#   hardpoint-wal-g wal-push PATH      archive one WAL segment (Postgres does this)
#   hardpoint-wal-g backup-push PGDATA a full base backup
#   hardpoint-wal-g backup-list        what's in the store; any other WAL-G command works too
set -euo pipefail

WALG_ENV_FILE=${WALG_ENV_FILE:-/etc/wal-g/env}
WALG_BIN=${WALG_BIN:-/opt/wal-g/wal-g}

if [ ! -r "$WALG_ENV_FILE" ] || [ ! -x "$WALG_BIN" ]; then
  # Not set up on this server (a fresh install, development). Archiving reports success so WAL
  # doesn't pile up and fill the disk; it's simply not kept, as before continuous backup existed.
  # config/backup/walg.sh check fails loudly in this state, so it can't go unnoticed in production.
  if [ "${1:-}" = "wal-push" ]; then exit 0; fi
  echo "wal-g: not configured (need $WALG_ENV_FILE and $WALG_BIN)" >&2
  exit 78
fi

set -a
# shellcheck disable=SC1090
. "$WALG_ENV_FILE"
set +a
exec "$WALG_BIN" "$@"
