#!/usr/bin/env bash
# Rebuilds the whole Postgres cluster as it was at a given moment, from the newest weekly base backup before
# that moment plus the archived WAL segments (docs/RUNBOOK.md, "Disaster recovery"). For losing the server
# (restore to "latest", the last shipped segment, about five minutes behind), or for undoing a bad
# migration or a mistaken bulk change (restore to just before it). Run on the VPS host as root.
#
#   restore_pitr.sh "2026-11-08 10:42:00+03"      # to that moment
#   restore_pitr.sh latest                          # to the end of the archive
#
# The hardpoint-db container must exist (bin/kamal accessory boot db, or already running); it is stopped,
# its data directory moved aside (never deleted), the base backup unpacked in its place with the WAL it
# needs, and Postgres started in recovery. Postgres replays to the target and promotes itself. Then start the
# app (bin/kamal app boot) and check a shop. Nothing here touches the backup bucket except to read it.
set -euo pipefail

[ -f /etc/hardpoint/backup.env ] && set -a && . /etc/hardpoint/backup.env && set +a
: "${BACKUP_PASSPHRASE:?}" "${S3_ENDPOINT:?}" "${S3_BUCKET:?}" "${S3_REGION:?}" "${S3_ACCESS_KEY:?}" "${S3_SECRET_KEY:?}"
DB_CONTAINER=${DB_CONTAINER:-hardpoint-db}
PGDATA_IN_VOLUME=${PGDATA_IN_VOLUME:-18/docker} # postgres:18 keeps its data under /var/lib/postgresql/18/docker

target=${1:?usage: $0 \"YYYY-MM-DD HH:MM:SS+03\"|latest}
log() { echo "$(date -u +%FT%TZ) restore_pitr: $*"; }
s3() { curl --fail --silent --show-error --aws-sigv4 "aws:amz:${S3_REGION}:s3" --user "${S3_ACCESS_KEY}:${S3_SECRET_KEY}" "$@"; }
decrypt() { openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:BACKUP_PASSPHRASE; }

# Every key under a prefix, oldest first (keys carry their timestamps), through the store's paging.
list_keys() { # prefix
  local token="" page
  while :; do
    page=$(s3 "${S3_ENDPOINT%/}/${S3_BUCKET}/?list-type=2&prefix=$1${token:+&continuation-token=$token}")
    echo "$page" | grep -o '<Key>[^<]*</Key>' | sed 's/<[^>]*>//g'
    token=$(echo "$page" | grep -o '<NextContinuationToken>[^<]*</NextContinuationToken>' | sed 's/<[^>]*>//g' | sed 's/%/%25/g;s/+/%2B/g;s/=/%3D/g;s#/#%2F#g') || true
    [ -n "$token" ] || break
  done | sort
}

# The newest base backup taken before the target (its name carries the time it started, in UTC).
if [ "$target" = "latest" ]; then
  base=$(list_keys base/hardpoint-base- | tail -1)
else
  cutoff=$(date -u -d "$target" +%Y%m%dT%H%M%SZ)
  base=$(list_keys base/hardpoint-base- | awk -v cutoff="$cutoff" '{ n = $0; sub(/.*hardpoint-base-/, "", n); sub(/\.tar\.enc$/, "", n); if (n <= cutoff) print }' | tail -1)
fi
[ -n "$base" ] || { log "no base backup before $target in s3://$S3_BUCKET/base/"; exit 1; }
log "base backup: $base"

volume=$(docker inspect "$DB_CONTAINER" --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql"}}{{.Source}}{{end}}{{end}}')
[ -n "$volume" ] || { log "can't find $DB_CONTAINER's data volume"; exit 1; }
pgdata="$volume/$PGDATA_IN_VOLUME"
archive="$volume/wal_archive"

docker stop "$DB_CONTAINER" > /dev/null && log "$DB_CONTAINER stopped"
if [ -d "$pgdata" ]; then
  aside="$pgdata.before-restore-$(date -u +%Y%m%dT%H%M%SZ)"
  mv "$pgdata" "$aside" && log "old data directory kept at $aside (remove it yourself once the restore is good)"
fi
mkdir -p "$pgdata" "$archive"

log "unpacking the base backup"
s3 "${S3_ENDPOINT%/}/${S3_BUCKET}/$base" | decrypt | tar -C "$pgdata" -xf -
start_segment=$(grep -o 'file [0-9A-F]*' "$pgdata/backup_label" | awk '{print $2}')
[ -n "$start_segment" ] || { log "backup_label has no starting WAL segment"; exit 1; }

log "fetching WAL from segment $start_segment"
fetched=0
while IFS= read -r key; do
  name=$(basename "$key" .enc)
  [ -f "$archive/$name" ] && continue
  s3 "${S3_ENDPOINT%/}/${S3_BUCKET}/$key" | decrypt > "$archive/$name.tmp" && mv "$archive/$name.tmp" "$archive/$name"
  fetched=$((fetched + 1))
done < <(list_keys wal/ | awk -v start="$start_segment" '{ n = $0; sub(/^wal\//, "", n); sub(/\.enc$/, "", n); if (substr(n, 1, 24) >= start) print }')
log "fetched $fetched segment(s)"

# Recovery settings: replay from the local archive to the target, then promote.
touch "$pgdata/recovery.signal"
{
  echo "restore_command = 'cp /var/lib/postgresql/wal_archive/%f %p'"
  if [ "$target" = "latest" ]; then
    echo "recovery_target_timeline = 'latest'"
  else
    echo "recovery_target_time = '$target'"
    echo "recovery_target_inclusive = false"
  fi
  echo "recovery_target_action = 'promote'"
} >> "$pgdata/postgresql.auto.conf"
chown -R 999:999 "$volume"
chmod 700 "$pgdata"

docker start "$DB_CONTAINER" > /dev/null && log "$DB_CONTAINER started in recovery; watching"
for _ in $(seq 1 600); do
  if docker exec "$DB_CONTAINER" pg_isready -q 2> /dev/null && [ "$(docker exec "$DB_CONTAINER" psql -U postgres -Atc 'SELECT pg_is_in_recovery()' 2> /dev/null)" = "f" ]; then
    log "recovered and promoted: the cluster is at $target"
    log "next: bin/kamal app boot, then sign in to a shop and check its latest sales; new WAL archives from here"
    exit 0
  fi
  sleep 2
done
log "still recovering after 20 minutes; follow docker logs $DB_CONTAINER"
exit 1
