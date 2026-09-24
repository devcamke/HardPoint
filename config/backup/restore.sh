#!/usr/bin/env bash
# Restores a database backup made by backup.sh (see docs/RUNBOOK.md, "Disaster recovery").
#
#   restore.sh hardpoint-db-20260924T010000Z.tar.enc            # a local file
#   restore.sh s3:hourly/hardpoint-db-20260924T010000Z.tar.enc  # fetched from the off-site store
#
# Checks the checksum, decrypts with BACKUP_PASSPHRASE, recreates the roles (existing ones are kept)
# and restores each database into an empty database of the same name (or TARGET_SUFFIX appended, e.g.
# "_drill", to restore alongside the live one). The app role owns everything, as before.
# pg_stat_statements is skipped (it needs a superuser; the Postgres accessory's first-boot script made it);
# other extensions, like pg_trgm for search, are trusted and restored with everything else.
set -euo pipefail

[ -f /etc/hardpoint/backup.env ] && set -a && . /etc/hardpoint/backup.env && set +a
: "${BACKUP_PASSPHRASE:?BACKUP_PASSPHRASE is required}"
PG_EXEC=${PG_EXEC:-"docker exec -i hardpoint-db"}
PG_USER=${PG_USER:-postgres}
APP_ROLE=${APP_ROLE:-hardpoint}
TARGET_SUFFIX=${TARGET_SUFFIX:-}

source=${1:?usage: $0 FILE|s3:KEY}
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
log() { echo "$(date -u +%FT%TZ) restore: $*"; }

if [[ "$source" == s3:* ]]; then
  key=${source#s3:}; file="$work/$(basename "$key")"
  for suffix in "" .sha256; do
    curl --fail --silent --show-error --aws-sigv4 "aws:amz:${S3_REGION}:s3" --user "${S3_ACCESS_KEY}:${S3_SECRET_KEY}" \
      -o "$file$suffix" "${S3_ENDPOINT%/}/${S3_BUCKET}/$key$suffix"
  done
else
  file=$source
fi

if [ -f "$file.sha256" ]; then
  [ "$(sha256sum "$file" | awk '{print $1}')" = "$(cat "$file.sha256")" ] || { log "checksum mismatch"; exit 1; }
  log "checksum ok"
fi

mkdir "$work/dump"
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:BACKUP_PASSPHRASE < "$file" | tar -C "$work/dump" -xf -

# Roles: create the ones that don't exist yet (a fresh server already has postgres and the app role).
grep -E '^(CREATE ROLE|ALTER ROLE)' "$work/dump/roles.sql" | grep -v -E "ROLE (postgres|\"postgres\")[ ;]" \
  | sed -E 's/^CREATE ROLE ([^;]+);/DO $$ BEGIN CREATE ROLE \1; EXCEPTION WHEN duplicate_object THEN NULL; END $$;/' \
  | $PG_EXEC psql -U "$PG_USER" -d postgres -q -v ON_ERROR_STOP=1 > /dev/null

for dump in "$work"/dump/*.dump; do
  db="$(basename "$dump" .dump)$TARGET_SUFFIX"
  log "restoring $db"
  $PG_EXEC psql -U "$PG_USER" -d postgres -q -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"$db\" OWNER \"$APP_ROLE\"" 2>/dev/null \
    || { [ "$($PG_EXEC psql -U "$PG_USER" -d "$db" -Atc "SELECT count(*) FROM pg_tables WHERE schemaname = 'public'")" = "0" ] \
         || { log "$db already has tables; restore into an empty database (or set TARGET_SUFFIX)"; exit 1; }; }
  $PG_EXEC pg_restore -l < "$dump" | grep -v 'pg_stat_statements' > "$work/list"
  # custom-format archives are read from stdin; the list file goes in through the container's /tmp
  $PG_EXEC sh -c "cat > /tmp/restore.list" < "$work/list"
  $PG_EXEC pg_restore -U "$PG_USER" -d "$db" --no-owner --role="$APP_ROLE" --exit-on-error --single-transaction \
    -L /tmp/restore.list < "$dump"
  $PG_EXEC rm -f /tmp/restore.list
done
log "done"
