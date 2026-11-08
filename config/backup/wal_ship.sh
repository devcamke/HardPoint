#!/usr/bin/env bash
# Ships Postgres' archived WAL segments off-site: every minute from cron on the VPS host (docs/RUNBOOK.md,
# "Backups"). Postgres copies each finished segment into the data volume's wal_archive directory
# (archive_command in config/postgres/postgresql.conf); this encrypts each one with AES-256 under
# BACKUP_PASSPHRASE, uploads it to s3://$S3_BUCKET/wal/<segment>.enc, checks the size that arrived, and only
# then deletes the local copy. A segment that fails to upload stays and is tried again next minute. When the
# oldest unshipped segment is more than STALE_MINUTES old the run fails (and the heartbeat isn't pinged), so
# silence from the heartbeat means the archive is falling behind.
#
# Settings come from /etc/hardpoint/backup.env (or the environment): BACKUP_PASSPHRASE, S3_ENDPOINT, S3_BUCKET,
# S3_REGION, S3_ACCESS_KEY, S3_SECRET_KEY and, optionally, WAL_HEARTBEAT_URL and WAL_ARCHIVE_DIR (found from the
# hardpoint-db container's data volume by default).
set -euo pipefail

[ -f /etc/hardpoint/backup.env ] && set -a && . /etc/hardpoint/backup.env && set +a
: "${BACKUP_PASSPHRASE:?BACKUP_PASSPHRASE is required}" "${S3_ENDPOINT:?}" "${S3_BUCKET:?}" "${S3_REGION:?}" "${S3_ACCESS_KEY:?}" "${S3_SECRET_KEY:?}"
DB_CONTAINER=${DB_CONTAINER:-hardpoint-db}
STALE_MINUTES=${STALE_MINUTES:-30}

log() { echo "$(date -u +%FT%TZ) wal_ship: $*"; }

if [ -z "${WAL_ARCHIVE_DIR:-}" ]; then
  volume=$(docker inspect "$DB_CONTAINER" --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql"}}{{.Source}}{{end}}{{end}}')
  [ -n "$volume" ] || { log "can't find $DB_CONTAINER's data volume; set WAL_ARCHIVE_DIR"; exit 1; }
  WAL_ARCHIVE_DIR="$volume/wal_archive"
fi
[ -d "$WAL_ARCHIVE_DIR" ] || { log "nothing archived yet ($WAL_ARCHIVE_DIR doesn't exist)"; exit 0; }

# One run at a time: a slow upload mustn't be joined by next minute's run.
exec 9> "/run/lock/hardpoint-wal-ship.lock"
flock -n 9 || exit 0

upload() { # file, key → the uploaded object's size
  curl --fail --silent --show-error --retry 3 --aws-sigv4 "aws:amz:${S3_REGION}:s3" --user "${S3_ACCESS_KEY}:${S3_SECRET_KEY}" \
    --upload-file "$1" "${S3_ENDPOINT%/}/${S3_BUCKET}/$2"
  curl --fail --silent --show-error --head --aws-sigv4 "aws:amz:${S3_REGION}:s3" --user "${S3_ACCESS_KEY}:${S3_SECRET_KEY}" \
    "${S3_ENDPOINT%/}/${S3_BUCKET}/$2" | tr -d '\r' | awk 'tolower($1) == "content-length:" { print $2 }'
}

work=$(mktemp -d /tmp/hardpoint-wal-ship.XXXXXX)
trap 'rm -rf "/tmp/${work#/tmp/}"' EXIT
shipped=0 failed=0

# Oldest first; .partial files are segments still being written.
while IFS= read -r name; do
  segment="$WAL_ARCHIVE_DIR/$name"
  encrypted="$work/$name.enc"
  openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass env:BACKUP_PASSPHRASE < "$segment" > "$encrypted"
  expected=$(stat -c %s "$encrypted")
  if arrived=$(upload "$encrypted" "wal/$name.enc") && [ "$arrived" = "$expected" ]; then
    rm -f -- "$segment"
    shipped=$((shipped + 1))
  else
    log "upload of $name failed (sent $expected bytes, store has ${arrived:-nothing}); will retry"
    failed=$((failed + 1))
  fi
  rm -f -- "$encrypted"
done < <(find "$WAL_ARCHIVE_DIR" -maxdepth 1 -type f ! -name '*.partial' -printf '%f\n' | sort)

[ "$shipped" -gt 0 ] && log "shipped $shipped segment(s)"
stale=$(find "$WAL_ARCHIVE_DIR" -maxdepth 1 -type f ! -name '*.partial' -mmin "+$STALE_MINUTES" | wc -l)
if [ "$failed" -gt 0 ] || [ "$stale" -gt 0 ]; then
  log "ARCHIVE BEHIND: $failed failed this run, $stale segment(s) older than $STALE_MINUTES minutes still here"
  exit 1
fi
[ -n "${WAL_HEARTBEAT_URL:-}" ] && curl --fail --silent --show-error --max-time 10 --retry 3 "$WAL_HEARTBEAT_URL" > /dev/null
exit 0
