#!/usr/bin/env bash
# Encrypted off-site backups of HardPoint, run on the VPS by cron (see docs/RUNBOOK.md):
#
#   backup.sh db      hourly: the app and job databases, plus roles  → s3://$S3_BUCKET/hourly/…
#                     (the run after midnight UTC is also copied to daily/)
#   backup.sh files   daily: uploaded files (Active Storage)          → s3://$S3_BUCKET/files/…
#
# Each backup is a pg_dump custom-format archive (or a tar of the storage volume) encrypted with
# AES-256 (openssl, PBKDF2) under BACKUP_PASSPHRASE, with a SHA-256 checksum. Uploads use curl's AWS
# signing, so any S3-compatible store works (Contabo Object Storage, Backblaze B2, AWS S3). How long
# copies are kept is set by the bucket's lifecycle rules: 2 days for hourly/, 35 for daily/ and files/.
# The last 48 hours also stay on the server in $BACKUP_DIR for quick restores.
#
# Settings come from /etc/hardpoint/backup.env (or the environment):
#   BACKUP_PASSPHRASE   required; keep a copy in the password manager, backups are useless without it
#   S3_ENDPOINT S3_BUCKET S3_REGION S3_ACCESS_KEY S3_SECRET_KEY   off-site store (skipped if unset)
#   BACKUP_HEARTBEAT_URL   optional; pinged after each success (e.g. healthchecks.io) so silence alerts
#   PG_EXEC             how to reach Postgres; default runs inside the Kamal accessory container
#   DATABASES           default "hardpoint_production hardpoint_production_queue"
#   STORAGE_DIR         default the Kamal storage volume
set -euo pipefail

[ -f /etc/hardpoint/backup.env ] && set -a && . /etc/hardpoint/backup.env && set +a

: "${BACKUP_PASSPHRASE:?BACKUP_PASSPHRASE is required}"
PG_EXEC=${PG_EXEC:-"docker exec -i hardpoint-db"}
PG_USER=${PG_USER:-postgres}
DATABASES=${DATABASES:-"hardpoint_production hardpoint_production_queue"}
STORAGE_DIR=${STORAGE_DIR:-/var/lib/docker/volumes/hardpoint_storage/_data}
BACKUP_DIR=${BACKUP_DIR:-/var/backups/hardpoint}
KEEP_LOCAL_HOURS=${KEEP_LOCAL_HOURS:-48}

stamp=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$BACKUP_DIR"
umask 077

log() { echo "$(date -u +%FT%TZ) backup: $*"; }

encrypt() { openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass env:BACKUP_PASSPHRASE; }

upload() { # file, key
  if [ -z "${S3_ENDPOINT:-}" ]; then log "S3 not configured; kept $1 locally only"; return; fi
  curl --fail --silent --show-error --retry 3 --aws-sigv4 "aws:amz:${S3_REGION}:s3" --user "${S3_ACCESS_KEY}:${S3_SECRET_KEY}" \
    --upload-file "$1" "${S3_ENDPOINT%/}/${S3_BUCKET}/$2"
}

ship() { # file, prefix
  local name; name=$(basename "$1")
  sha256sum "$1" | awk '{print $1}' > "$1.sha256"
  upload "$1" "$2/$name"
  upload "$1.sha256" "$2/$name.sha256"
}

backup_db() {
  local file="$BACKUP_DIR/hardpoint-db-$stamp.tar.enc" work; work=$(mktemp -d)
  trap 'rm -rf "$work"' RETURN
  $PG_EXEC pg_dumpall -U "$PG_USER" --roles-only > "$work/roles.sql"
  for db in $DATABASES; do
    $PG_EXEC pg_dump -U "$PG_USER" --format=custom --compress="${DUMP_COMPRESS:-zstd:6}" "$db" > "$work/$db.dump"
  done
  tar -C "$work" -cf - . | encrypt > "$file"
  log "database backup $(basename "$file") ($(du -h "$file" | cut -f1))"
  ship "$file" hourly
  if [ "$(date -u +%H)" = "00" ]; then ship "$file" daily; fi
}

backup_files() {
  local file="$BACKUP_DIR/hardpoint-files-$stamp.tar.enc"
  tar -C "$STORAGE_DIR" -czf - . | encrypt > "$file"   # images are already compressed; gzip is enough
  log "files backup $(basename "$file") ($(du -h "$file" | cut -f1))"
  ship "$file" files
}

case "${1:-}" in
  db) backup_db ;;
  files) backup_files ;;
  *) echo "usage: $0 db|files" >&2; exit 64 ;;
esac

find "$BACKUP_DIR" -name 'hardpoint-*' -mmin +$((KEEP_LOCAL_HOURS * 60)) -delete
[ -n "${BACKUP_HEARTBEAT_URL:-}" ] && curl -fsS -m 10 --retry 3 "$BACKUP_HEARTBEAT_URL" > /dev/null
log "done"
