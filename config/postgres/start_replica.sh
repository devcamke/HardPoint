#!/bin/bash
# The db-replica accessory's command (config/deploy.scaled.yml). On first start, with an empty data
# directory, it copies the primary with pg_basebackup through a replication slot, so the primary
# keeps the WAL the replica still needs; -R writes standby.signal and the connection settings.
# After that Postgres starts as a read-only hot standby that follows the primary.
set -euo pipefail

export PGDATA=${PGDATA:-/var/lib/postgresql/18/docker}

if [ ! -s "$PGDATA/PG_VERSION" ]; then
  mkdir -p "$PGDATA"
  chown -R postgres:postgres "$(dirname "$PGDATA")"
  chmod 700 "$PGDATA"
  PGPASSWORD="$REPLICATION_PASSWORD" gosu postgres pg_basebackup \
    --host="$PRIMARY_HOST" --username=replicator --pgdata="$PGDATA" \
    --wal-method=stream --write-recovery-conf --create-slot --slot=hardpoint_replica --progress
fi

exec gosu postgres postgres -c config_file=/etc/postgresql/postgresql.conf -c hot_standby=on
