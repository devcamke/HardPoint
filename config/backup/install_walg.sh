#!/usr/bin/env bash
# Installs WAL-G on the database server's host for continuous backup (docs/RUNBOOK.md §2):
#   /opt/hardpoint/wal-g/wal-g   the binary, a pinned release checked against its SHA-256
#   /etc/hardpoint/wal-g/env     its settings (a template the first time; fill it in)
# Both are mounted read-only into the Postgres accessory (config/deploy.yml). Safe to run again,
# e.g. after changing WALG_VERSION and WALG_SHA256 to upgrade.
set -euo pipefail

WALG_VERSION=${WALG_VERSION:-v3.0.7}
WALG_SHA256=${WALG_SHA256:-76d51ed915165d45314bc947300b9d1776adb2d875d857f580a730fd6f66900e}
ASSET=wal-g-pg-ubuntu-22.04-amd64 # needs only glibc, so it runs inside the Debian postgres:18 image
POSTGRES_UID=${POSTGRES_UID:-999} # the postgres user in the official image

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
curl --fail --silent --show-error --location --retry 3 -o "$work/walg.tar.gz" \
  "https://github.com/wal-g/wal-g/releases/download/${WALG_VERSION}/${ASSET}.tar.gz"
echo "${WALG_SHA256}  $work/walg.tar.gz" | sha256sum --check --quiet
tar -C "$work" -xzf "$work/walg.tar.gz"
install -d -m 755 /opt/hardpoint/wal-g
install -m 755 "$work/$ASSET" /opt/hardpoint/wal-g/wal-g
/opt/hardpoint/wal-g/wal-g --version

install -d -m 750 -o root -g "$POSTGRES_UID" /etc/hardpoint/wal-g
if [ ! -f /etc/hardpoint/wal-g/env ]; then
  cat > /etc/hardpoint/wal-g/env <<'ENV'
# WAL-G settings for continuous backup, read inside the Postgres container. Keep a copy of the
# whole file in the team password manager: without WALG_LIBSODIUM_KEY the backups can't be read.
WALG_S3_PREFIX=s3://hardpoint-wal/production
AWS_ENDPOINT=https://eu2.contabostorage.com
AWS_REGION=default
AWS_S3_FORCE_PATH_STYLE=true
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
# 32 random bytes as hex: openssl rand -hex 32
WALG_LIBSODIUM_KEY=
WALG_LIBSODIUM_KEY_TRANSFORM=hex
WALG_COMPRESSION_METHOD=zstd
WALG_UPLOAD_CONCURRENCY=4
# How WAL-G reaches Postgres for base backups (the container's own socket).
PGHOST=/var/run/postgresql
PGUSER=postgres
ENV
  echo "Wrote /etc/hardpoint/wal-g/env: fill it in, then restart the db accessory (bin/kamal accessory reboot db)"
fi
chown root:"$POSTGRES_UID" /etc/hardpoint/wal-g/env
chmod 640 /etc/hardpoint/wal-g/env
