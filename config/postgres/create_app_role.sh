#!/bin/bash
# Runs once, when the postgres:18 accessory initialises an empty data directory.
# The app must not connect as a superuser or BYPASSRLS role: those skip row-level security.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres -v password="$HARDPOINT_DATABASE_PASSWORD" <<'SQL'
CREATE ROLE hardpoint LOGIN CREATEDB NOSUPERUSER NOBYPASSRLS PASSWORD :'password';
SQL
