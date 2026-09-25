#!/bin/bash
# Runs once, when the postgres:18 accessory initialises an empty data directory.
# The app must not connect as a superuser or BYPASSRLS role: those skip row-level security.
# The main database is made here (owned by the app) so the pg_stat_statements extension, which
# needs a superuser to install, can be added to it; the app's `db:prepare` finds it in place.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres -v password="$HARDPOINT_DATABASE_PASSWORD" <<'SQL'
CREATE ROLE hardpoint LOGIN CREATEDB NOSUPERUSER NOBYPASSRLS PASSWORD :'password';
-- Lets the admin Database page read query statistics for every role (read-only).
GRANT pg_read_all_stats TO hardpoint;
CREATE DATABASE hardpoint_production OWNER hardpoint;
SQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname hardpoint_production <<'SQL'
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
SQL

# For a streaming read replica (config/deploy.scaled.yml): a role that may only replicate, allowed
# in from the private network. Skipped on a single server, where REPLICATION_PASSWORD isn't set.
if [ -n "${REPLICATION_PASSWORD:-}" ]; then
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres -v password="$REPLICATION_PASSWORD" <<'SQL'
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD :'password';
SQL
  echo "host replication replicator ${PRIVATE_NETWORK:-10.0.0.0/24} scram-sha-256" >> "$PGDATA/pg_hba.conf"
fi
