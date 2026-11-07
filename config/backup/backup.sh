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
# Each run checks its own work before it counts: every dump is read back with pg_restore --list,
# the encrypted file is decrypted and listed, and each upload's size is compared with the original.
# The heartbeat is pinged only when all of that passed; any failure pings its /fail address with
# the reason, so the alert says what broke. A run with no off-site store configured fails (copies
# that never leave the server don't survive losing it) unless ALLOW_LOCAL_ONLY=1, for staging.
#
# Settings come from /etc/hardpoint/backup.env (or the environment):
#   BACKUP_PASSPHRASE   required; keep a copy in the password manager, backups are useless without it
#   S3_ENDPOINT S3_BUCKET S3_REGION S3_ACCESS_KEY S3_SECRET_KEY   off-site store (skipped if unset)
#   BACKUP_HEARTBEAT_URL   optional; pinged after each success (e.g. healthchecks.io) so silence alerts,
#                          and its /fail address with the reason when a run fails
#   ALLOW_LOCAL_ONLY    set to 1 to keep backups on the server only (staging); otherwise S3 is required
#   PG_EXEC             how to reach Postgres; default runs inside the Kamal accessory container
#   DATABASES           default "hardpoint_production hardpoint_production_queue"
#   STORAGE_DIR         default the Kamal storage volume
set -Eeuo pipefail

[ -f /etc/hardpoint/backup.env ] && set -a && . /etc/hardpoint/backup.env && set +a

log() { echo "$(date -u +%FT%TZ) backup: $*"; }

# Tells the heartbeat what broke, then stops. Also runs for any command that fails unexpectedly.
fail() {
  log "FAILED: $*"
  if [ -n "${BACKUP_HEARTBEAT_URL:-}" ]; then
    curl -fsS -m 10 --retry 3 --data-raw "backup ${MODE:-}: $*" "${BACKUP_HEARTBEAT_URL%/}/fail" > /dev/null || true
  fi
  exit 1
}
trap 'fail "stopped unexpectedly at line $LINENO"' ERR
MODE=${1:-}

[ -n "${BACKUP_PASSPHRASE:-}" ] || fail "BACKUP_PASSPHRASE is required"
[ "${#BACKUP_PASSPHRASE}" -ge 20 ] || fail "BACKUP_PASSPHRASE is too short (use 20 or more random characters)"
if [ -z "${S3_ENDPOINT:-}" ] && [ "${ALLOW_LOCAL_ONLY:-}" != "1" ]; then
  fail "no off-site store configured (S3_ENDPOINT etc.); set ALLOW_LOCAL_ONLY=1 to keep backups on this server only"
fi
PG_EXEC=${PG_EXEC:-"docker exec -i hardpoint-db"}
PG_USER=${PG_USER:-postgres}
DATABASES=${DATABASES:-"hardpoint_production hardpoint_production_queue"}
STORAGE_DIR=${STORAGE_DIR:-/var/lib/docker/volumes/hardpoint_storage/_data}
BACKUP_DIR=${BACKUP_DIR:-/var/backups/hardpoint}
KEEP_LOCAL_HOURS=${KEEP_LOCAL_HOURS:-48}

stamp=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$BACKUP_DIR"
umask 077

encrypt() { openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass env:BACKUP_PASSPHRASE; }

s3() { curl --fail --silent --show-error --retry 3 --aws-sigv4 "aws:amz:${S3_REGION}:s3" --user "${S3_ACCESS_KEY}:${S3_SECRET_KEY}" "$@"; }

upload() { # file, key; then checks the store holds the whole file
  if [ -z "${S3_ENDPOINT:-}" ]; then log "kept $1 on this server only (ALLOW_LOCAL_ONLY)"; return; fi
  local url="${S3_ENDPOINT%/}/${S3_BUCKET}/$2" stored
  s3 --upload-file "$1" "$url" || fail "upload of $2 failed"
  stored=$(s3 --head "$url" | tr -d '\r' | awk 'tolower($1) == "content-length:" { print $2 }')
  [ "$stored" = "$(stat -c %s "$1")" ] || fail "$2 is ${stored:-missing} bytes in the store, $(stat -c %s "$1") here"
}

# The encrypted file decrypts and its archive lists, so it isn't truncated or under another passphrase.
verify_encrypted() { # file, tar flags
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:BACKUP_PASSPHRASE < "$1" | tar "-t$2f" - > /dev/null \
    || fail "$(basename "$1") doesn't decrypt and list"
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
  [ -s "$work/roles.sql" ] || fail "pg_dumpall --roles-only wrote nothing"
  for db in $DATABASES; do
    $PG_EXEC pg_dump -U "$PG_USER" --format=custom --compress="${DUMP_COMPRESS:-zstd:6}" "$db" > "$work/$db.dump" \
      || fail "pg_dump of $db failed"
    # A complete custom-format archive has a table of contents pg_restore can read.
    $PG_EXEC pg_restore --list < "$work/$db.dump" | grep -c "TABLE DATA" > /dev/null || fail "the dump of $db can't be read back"
  done
  tar -C "$work" -cf - . | encrypt > "$file"
  verify_encrypted "$file" ""
  log "database backup $(basename "$file") ($(du -h "$file" | cut -f1))"
  ship "$file" hourly
  if [ "$(date -u +%H)" = "00" ]; then ship "$file" daily; fi
}

backup_files() {
  local file="$BACKUP_DIR/hardpoint-files-$stamp.tar.enc"
  [ -d "$STORAGE_DIR" ] || fail "$STORAGE_DIR doesn't exist"
  tar -C "$STORAGE_DIR" -czf - . | encrypt > "$file"   # images are already compressed; gzip is enough
  verify_encrypted "$file" z
  log "files backup $(basename "$file") ($(du -h "$file" | cut -f1))"
  ship "$file" files
}

case "${1:-}" in
  db) backup_db ;;
  files) backup_files ;;
  *) trap - ERR; echo "usage: $0 db|files" >&2; exit 64 ;;
esac

find "$BACKUP_DIR" -name 'hardpoint-*' -mmin +$((KEEP_LOCAL_HOURS * 60)) -delete
if [ -n "${BACKUP_HEARTBEAT_URL:-}" ]; then
  curl -fsS -m 10 --retry 3 "$BACKUP_HEARTBEAT_URL" > /dev/null || log "couldn't reach the heartbeat (the backup itself is fine)"
fi
log "done"
