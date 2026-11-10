#!/usr/bin/env bash
# Refreshes the staging server from production's newest hourly backup, then scrambles the people in it
# (bin/rails staging:anonymise). Run on the staging VPS as root, with /etc/hardpoint/backup.env holding the
# read key for the backup bucket and BACKUP_PASSPHRASE; STAGING_PASSWORD is the password every account gets.
# Doubles as the monthly restore drill: it proves the newest backup restores and boots the app.
#
#   STAGING_PASSWORD=... /opt/hardpoint/refresh_staging.sh
set -euo pipefail

[ -f /etc/hardpoint/backup.env ] && set -a && . /etc/hardpoint/backup.env && set +a
: "${BACKUP_PASSPHRASE:?}" "${S3_ENDPOINT:?}" "${S3_BUCKET:?}" "${S3_REGION:?}" "${S3_ACCESS_KEY:?}" "${S3_SECRET_KEY:?}" "${STAGING_PASSWORD:?}"
PG_EXEC=${PG_EXEC:-"docker exec -i hardpoint-db"}
DATABASES=${DATABASES:-"hardpoint_production hardpoint_production_queue"}
SERVICE=${SERVICE:-hardpoint}

log() { echo "$(date -u +%FT%TZ) refresh: $*"; }
s3_get() { curl --fail --silent --show-error --aws-sigv4 "aws:amz:${S3_REGION}:s3" --user "${S3_ACCESS_KEY}:${S3_SECRET_KEY}" "$@"; }

# The newest hourly backup in the bucket (keys sort by their timestamp).
newest=$(s3_get "${S3_ENDPOINT%/}/${S3_BUCKET}/?list-type=2&prefix=hourly/hardpoint-db-" | grep -o '<Key>[^<]*\.tar\.enc</Key>' | sed 's/<[^>]*>//g' | sort | tail -1)
[ -n "$newest" ] || { log "no hourly backup found in s3://${S3_BUCKET}/hourly/"; exit 1; }
log "restoring $newest"

web=$(docker ps --filter "label=service=${SERVICE}" --filter "label=role=web" -q)
[ -n "$web" ] && docker stop $web > /dev/null && log "app stopped"

for db in $DATABASES; do
  $PG_EXEC psql -U postgres -d postgres -q -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS \"$db\" WITH (FORCE)"
done
"$(dirname "$0")/restore.sh" "s3:$newest"

[ -n "$web" ] && docker start $web > /dev/null && log "app started"
web=$(docker ps --filter "label=service=${SERVICE}" --filter "label=role=web" -q | head -1)
for _ in $(seq 1 30); do docker exec "$web" curl -fs http://localhost/up > /dev/null 2>&1 && break; sleep 2; done

docker exec -e STAGING_PASSWORD="$STAGING_PASSWORD" "$web" bin/rails db:migrate staging:anonymise
log "done: staging is last night's production, scrambled"
