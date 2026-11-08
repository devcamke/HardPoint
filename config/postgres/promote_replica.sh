#!/usr/bin/env bash
# Fails over to the streaming replica (config/deploy.scaled.yml) when the primary is lost: makes the replica
# the new primary and points the app at it. Run from the deploying machine, where bin/kamal works, with the
# replica's private address (docs/RUNBOOK.md, "Scaling out", "Losing the primary"). Rehearse it at the
# monthly drill; it takes a few minutes, and the tills keep selling offline meanwhile.
#
#   config/postgres/promote_replica.sh 10.0.0.22
#
# What it does: 1. promotes the replica's Postgres (it stops following the old primary and accepts writes);
# 2. tells you the two lines to change in config/deploy.scaled.yml; 3. you redeploy so the app uses it. Reads
# that used to go to the replica go to the new primary until a new replica is built (RUNBOOK §6 step 2).
set -euo pipefail

replica=${1:?usage: $0 REPLICA_PRIVATE_ADDRESS}
destination=${KAMAL_DESTINATION:-scaled}
pgdata=${PGDATA:-/var/lib/postgresql/18/docker}

echo "Promoting the replica at $replica..."
bin/kamal accessory exec db-replica -d "$destination" --reuse "gosu postgres pg_ctl promote -D $pgdata -w"
bin/kamal accessory exec db-replica -d "$destination" --reuse "psql -U postgres -Atc 'SELECT pg_is_in_recovery()'" | grep -q '^f$' \
  && echo "The replica accepts writes now."

cat <<TEXT

Now, in config/deploy.scaled.yml:
  1. set DATABASE_HOST to $replica (the promoted server);
  2. remove DATABASE_REPLICA_HOST (reads go to the new primary until a new replica is built);
  3. deploy: bin/kamal deploy -d $destination
Then install the WAL shipping cron on $replica (docs/RUNBOOK.md §2): a promoted replica starts archiving
but nothing uploads it until cron runs config/backup/wal_ship.sh there. Take a base backup right away:
  /opt/hardpoint/backup.sh base
TEXT
