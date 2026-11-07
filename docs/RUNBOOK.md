# HardPoint runbook

How to run HardPoint in production: first setup, backups, disaster recovery, routine care and the
common incidents. Everything starts on one Contabo VPS behind Cloudflare, deployed with Kamal
(`config/deploy.yml`); the database is the Kamal `db` accessory (PostgreSQL 18). Section 6 covers
growing onto several servers.

## Targets

| | Target | How |
|---|---|---|
| **RPO** (data that can be lost) | **about 1 minute** | WAL-G ships every WAL segment off-site as it's finished (at least every minute), on top of a daily base backup; the hourly encrypted dump is a second, independent copy (1 hour); files daily |
| **RTO** (time to be selling again) | **2 hours** | Fresh VPS, Kamal setup, restore the latest base backup and replay WAL (steps below) |
| **Undo a mistake** | to the second, within 35 days | Point-in-time restore (section 3) to just before a bad import or a mass delete |
| Tills during an outage | keep selling | The offline till (Phase 8) takes cash and typed M-Pesa codes and sends the sales when the server is back |

## 1. First setup

1. **VPS** (Ubuntu 24.04, Cloud VPS 20 or bigger): a non-root deploy user with SSH keys only, root and
   password logins off; `ufw` allowing 22 from your address and 80/443 only from
   [Cloudflare's ranges](https://www.cloudflare.com/ips/); `fail2ban`, `unattended-upgrades`, a 4 GB
   swap file, time sync; Docker. Turn on Contabo's snapshot for the disk as an extra safety net.
2. **Cloudflare:** `hardpoint.app` and `*.hardpoint.app` proxied to the VPS; SSL **Full (strict)** with an
   Origin CA certificate for both (its PEM files go in `.kamal/secrets`); WAF managed rules; a rate
   limiting rule on `POST /session`; caching for `/assets/*`.
3. **Email:** verify the domain in AWS SES (DKIM, SPF, DMARC), request production access, create SMTP
   credentials and add them with `bin/rails credentials:edit` under `ses:`.
4. **Secrets:** `RAILS_MASTER_KEY`, `POSTGRES_PASSWORD`, `HARDPOINT_DATABASE_PASSWORD` and the origin
   certificate in the environment `.kamal/secrets` reads. Run `bin/rails db:encryption:init` once and
   store the keys in credentials. Keep a copy of the master key and the backup passphrase in the team
   password manager: **without them, backups can't be read**.
5. **Deploy:** `bin/kamal setup` (boots Postgres with `config/postgres/postgresql.conf` and its first-boot
   script, which creates the app role, the database and `pg_stat_statements`), then `bin/kamal deploy`.
6. **Integrations and billing:** see the README's Deployment section (M-Pesa, eTIMS, SMS, Paystack).
7. **Backups:** section 2. Then do the drill in section 3 before the first shop signs up.

## 2. Backups

Two independent layers, each encrypted, off-site and watched by its own heartbeat:

| | What | When | Restores |
|---|---|---|---|
| **Continuous (WAL-G)** | Physical base backup + every WAL segment | WAL as it's written (≤1 min); base daily | The whole cluster to any second in the last 35 days (§3) |
| **Logical dumps (`backup.sh`)** | `pg_dump` of each database, roles, and the uploads folder | Hourly; files daily | One database, or as a second opinion if WAL-G's store is damaged (§3) |

### Continuous backup with WAL-G

Postgres hands each finished WAL segment to WAL-G (`archive_command` in
`config/postgres/postgresql.conf`, through `config/postgres/wal-g.sh`), which compresses it with zstd,
encrypts it with libsodium and uploads it; `archive_timeout = 60` closes a segment at least every
minute when anything was written. A daily base backup gives replay a starting point. The WAL-G binary
(a pinned release, checked against its SHA-256) and its settings live on the host and are mounted
read-only into the `db` accessory (`config/deploy.yml`). Until they're there, archiving is a no-op,
so a fresh server never fills its disk with WAL, and `walg.sh check` fails until it's set up.

1. A **separate bucket** for WAL (`hardpoint-wal`), in another region from the server, with its own key.
2. On the database server:
   ```sh
   sudo install -d -m 700 /opt/hardpoint
   sudo install -m 700 config/backup/*.sh config/postgres/wal-g.sh /opt/hardpoint/
   sudo /opt/hardpoint/install_walg.sh            # binary + /etc/hardpoint/wal-g/env template
   sudo editor /etc/hardpoint/wal-g/env           # bucket, keys, WALG_LIBSODIUM_KEY=$(openssl rand -hex 32)
   ```
   Put the whole `env` file in the password manager: **without `WALG_LIBSODIUM_KEY` the WAL can't be read.**
3. `bin/kamal accessory reboot db` (picks up the mounts and `archive_mode = on`; a restart, so after
   closing time), then the first base backup: `sudo /opt/hardpoint/walg.sh base`.
4. Cron (added to the file below) and a healthchecks.io check expecting a ping every 15 minutes, as
   `WALG_HEARTBEAT_URL` in `/etc/hardpoint/backup.env`. `walg.sh check` fails, and pings `/fail` with
   the reason, if WAL-G isn't configured, archiving is failing, more than 100 segments are waiting
   (WAL piling up on the server's disk), or the newest base backup is over 26 hours old.
5. Bucket lifecycle: delete everything after **35 days**. That's safe with daily full base backups:
   every base backup still in the bucket has all of its later WAL there too. Use a key that can write
   but not delete. (With a key that can delete, `WALG_RETAIN_FULL=35` has WAL-G prune instead.)

`sudo /opt/hardpoint/walg.sh list` shows the base backups.

### Logical dumps

`config/backup/backup.sh` runs on the VPS host (not in a container). It dumps the app and job databases
with `pg_dump` inside the `hardpoint-db` container, encrypts with AES-256 under `BACKUP_PASSPHRASE`, and
uploads to an S3-compatible bucket (Contabo Object Storage in another region, or Backblaze B2) with a
checksum. Uploaded files (Active Storage) are backed up daily the same way.

```sh
sudo install -d -m 700 /opt/hardpoint /etc/hardpoint
sudo install -m 700 config/backup/*.sh /opt/hardpoint/
sudo tee /etc/hardpoint/backup.env > /dev/null <<'ENV'
BACKUP_PASSPHRASE=...            # long and random; also in the password manager
S3_ENDPOINT=https://eu2.contabostorage.com
S3_BUCKET=hardpoint-backups
S3_REGION=default
S3_ACCESS_KEY=...
S3_SECRET_KEY=...
BACKUP_HEARTBEAT_URL=https://hc-ping.com/...   # alerts if backups stop
WALG_HEARTBEAT_URL=https://hc-ping.com/...     # continuous backup (walg.sh check), every 15 minutes
ENV
sudo chmod 600 /etc/hardpoint/backup.env
sudo tee /etc/cron.d/hardpoint-backup > /dev/null <<'CRON'
17 * * * * root /opt/hardpoint/backup.sh db    >> /var/log/hardpoint-backup.log 2>&1
47 1 * * * root /opt/hardpoint/backup.sh files >> /var/log/hardpoint-backup.log 2>&1
23 0 * * * root /opt/hardpoint/walg.sh base    >> /var/log/hardpoint-backup.log 2>&1
*/15 * * * * root /opt/hardpoint/walg.sh check >> /var/log/hardpoint-backup.log 2>&1
CRON
```

Bucket lifecycle rules: delete `hourly/` after 2 days and `daily/` and `files/` after 35 days. Use a
bucket key that can write but not delete, so a compromised server can't wipe its own backups
(lifecycle rules do the deleting). The last 48 hours also stay in `/var/backups/hardpoint` on the VPS.

Each run checks its own work before the heartbeat is pinged: every dump is read back with
`pg_restore --list`, the encrypted file is decrypted and listed, and each upload's size in the bucket
is compared with the original. A failed run pings the heartbeat's `/fail` address with the reason. A
run with no off-site store configured **fails** (copies that never leave the server don't survive
losing it); set `ALLOW_LOCAL_ONLY=1` only on staging.

The heartbeat check should expect a ping every hour; if one is missed, check
`/var/log/hardpoint-backup.log`.

### Shops' own backups

Separate from the above: each shop's owners get their own verified backups under **Settings › Your
data › Backups** (`AccountBackup`). `AccountBackupScheduleJob` runs hourly and starts each shop's
daily, weekly or monthly backup once 02:00 has passed in the shop's time zone (one per period, so a
missed hour is caught up). At most two run at once across all shops (`AccountBackupJob`, queue
`backups`), reading from the replica when there is one, in one repeatable-read snapshot. Each ZIP is
checked against its manifest of SHA-256 checksums and row counts, uploaded, then downloaded again and
compared before it counts as good. Failures retry three times; then the owners are emailed, support
(`SUPPORT_EMAIL`) gets the details and `Rails.error` is reported. The nightly `AccountMaintenanceJob`
deletes backups past their time and fails any stuck for 6 hours (a worker killed by a deploy).

Storage: set `BACKUP_STORAGE_SERVICE=backups` and `BACKUP_STORAGE_ENDPOINT`, `_BUCKET`, `_REGION`,
`_ACCESS_KEY_ID` and `_SECRET_ACCESS_KEY` (`config/storage.yml`) to keep them in a private bucket in
another region, with server-side encryption on. Without it they go to the main Active Storage
service, which on one VPS is the same disk as everything else. Owners download them from the app;
restoring a shop from one is a support job (the CSVs carry every id), so for a whole-shop rollback
use the hourly database backups above.

Watching it: `AccountBackup.where(status: "failed", created_at: 1.day.ago..).count` should be 0, and
`AccountBackup.in_progress.where(created_at: ..3.hours.ago)` empty after 05:00 Nairobi.

## 3. Disaster recovery (and the monthly drill)

The same steps rebuild production after losing the server, and prove the backups work. **Do the drill
monthly** and after any change to the database setup: restore into a scratch database on the live
server (`TARGET_SUFFIX=_drill`) or onto a fresh VPS, check it, and note the time taken below.

1. **New VPS**, set up as in section 1 steps 1 and 5 (`bin/kamal setup` with the same secrets; point
   `servers` and the accessory `host` in `config/deploy.yml` at the new address). Stop the app while
   restoring: `bin/kamal app stop`.
2. **Restore the database** with WAL-G, to the last second the archive holds (install WAL-G first:
   section 2, steps 2 and the `env` file from the password manager). Stop the empty `db` accessory
   Kamal just booted and clear its data directory, then:
   ```sh
   bin/kamal accessory stop db
   sudo mv ~/hardpoint-db/data ~/hardpoint-db/data.empty     # the accessory's `data` directory
   sudo /opt/hardpoint/walg_restore.sh ~/hardpoint-db/data   # add --time "…" to stop earlier
   bin/kamal accessory boot db
   ```
   Postgres replays the WAL (`bin/kamal accessory logs db` shows "archive recovery complete"), then
   opens on a new timeline. Then, in `psql` as postgres: `ALTER SYSTEM RESET restore_command; ALTER
   SYSTEM RESET recovery_target_time; ALTER SYSTEM RESET recovery_target_action; SELECT
   pg_reload_conf();` and take a fresh base backup: `sudo /opt/hardpoint/walg.sh base`.

   **If WAL-G's store is unusable**, restore the newest hourly dump instead (up to an hour lost):
   ```sh
   /opt/hardpoint/restore.sh s3:hourly/hardpoint-db-<newest>.tar.enc
   ```
   It checks the checksum, decrypts, recreates roles and restores `hardpoint_production` and
   `hardpoint_production_queue` into the empty databases (the cache and cable databases rebuild
   themselves). It refuses to restore over a database that already has tables.
3. **Restore files:** fetch the newest `files/` backup, then
   `openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:BACKUP_PASSPHRASE < FILE | sudo tar -C /var/lib/docker/volumes/hardpoint_storage/_data -xzf -`.
4. **Start and check:** `bin/kamal app boot`; `bin/rails db:migrate:status` via `bin/kamal console`
   shows nothing pending; sign in to a shop, open the till, look at today's sales; the admin
   Database page shows sensible sizes.
5. **Cloudflare:** change the two DNS records to the new address (proxied, so it takes effect in
   seconds).
6. **Tills** that sold offline send their sales by themselves once they can reach the server. Sales
   made online in the gap between the last archived WAL (about a minute) and the outage are lost: tell the affected shops
   (Activity shows what arrived), and they can re-enter them from their paper receipts.

### Undoing a mistake (point-in-time restore)

A bad product import, a mass delete, a migration gone wrong: restore the whole cluster to just
before it. Everything after that moment is lost for **every** shop, so first try fixing it forward
from the hourly dump (`TARGET_SUFFIX=_drill`, then copy the rows back). If you do roll back: find the
moment in Activity or the logs, put up the maintenance notice, then follow step 2 above with
`--time "2026-11-07 14:31:00+03"`. Tills keep selling offline meanwhile and send their sales after.

**Drill (monthly, alongside the live database):** restore into a scratch directory and run it as a
throwaway container on another port; `--drill` stops the copy archiving into production's store.

```sh
sudo /opt/hardpoint/walg_restore.sh /var/tmp/pitr-drill --drill --time "$(date -d '1 hour ago' '+%F %T%z')"
docker run --rm -d --name pitr-drill -v /var/tmp/pitr-drill:/var/lib/postgresql \
  -v /opt/hardpoint/wal-g:/opt/wal-g:ro -v /etc/hardpoint/wal-g:/etc/wal-g:ro \
  -v /opt/hardpoint/wal-g.sh:/usr/local/bin/hardpoint-wal-g:ro postgres:18
docker logs -f pitr-drill            # until "database system is ready to accept connections"
docker exec pitr-drill psql -U postgres -d hardpoint_production -c "SELECT max(created_at) FROM sales"
docker rm -f pitr-drill && sudo rm -rf /var/tmp/pitr-drill
```

### Drill log

| Date | Where | Backup | Restore | Checks |
|---|---|---|---|---|
| 2026-11-07 | Local, PostgreSQL 16, WAL-G v3.0.7, file store | WAL archived through `wal-g.sh`, encrypted; base backup 1 s | `walg_restore.sh --time` 1 s, replay under 1 s | Stopped "before commit of transaction 733" at the target; the 1,500 rows written before it present, the delete and insert after it absent; promoted to timeline 2. `walg.sh check` caught: not configured, archiving failing (and recovered), stale base backup |
| 2026-09-24 | Local container, PostgreSQL 16, 25 MB database | 0.4 s | 0.9 s | Row counts of all 66 tables identical; RLS enabled and forced on 56 tables with 56 policies; all tables owned by the app role; 273 indexes; as the app role one shop sees its 310 sales and no shop sees none; the app boots against the copy and runs reports |

Restoring grows roughly with the database size (about a minute per gigabyte on NVMe is a fair first
guess); time it on the real server at the first drill and adjust the RTO if needed.

## 4. Routine care

- **Weekly:** merge Dependabot's pull requests once CI is green (it runs Brakeman, bundler-audit and
  importmap audit weekly even without commits); deploy.
- **Monthly:** the restore drill (section 3); look at the admin **Database** page: cache hit rates
  below 99% mean Postgres wants more memory, "Dead rows" much higher than live rows means vacuum is
  behind, and the slowest queries show where to add an index; check the VPS disk (`df -h`) and the
  backup bucket's size.
- **Every 3 months:** rotate the Paystack, M-Pesa and SMS API keys and the SES SMTP password; review
  who has platform admin (`User.where(admin: true)`).
- **Yearly:** renew the Cloudflare Origin CA certificate before it expires (15-year certificates avoid
  this); re-run pgtune if the VPS size changed.

## 5. Incidents

| Symptom | First steps |
|---|---|
| Site down | `bin/kamal app details`, `bin/kamal logs`; `curl -I https://hardpoint.app/up`. Tills keep selling offline meanwhile. |
| "could not obtain a connection" / "too many connections" | Pool too small for its threads, or Postgres' `max_connections` spent: see the connection budget in section 6 before raising either |
| Slow | Admin Database page: long-running queries and connections; `bin/kamal accessory logs db` for slow-query lines (over 500 ms are logged); raise `WEB_CONCURRENCY` if CPU is spare |
| Database full or disk full | `df -h`; old local backups are in `/var/backups/hardpoint`; `docker system prune` for old images |
| Emails not arriving | SES sending statistics and suppression list; bounces |
| M-Pesa payments not arriving | Shop's Settings › M-Pesa "Test connection"; Safaricom's callback IP list (`MPESA_CALLBACK_IPS`) |
| eTIMS queue growing | Settings › KRA eTIMS › Submissions shows the errors; KRA outages retry by themselves |
| A shop reports seeing another shop's data | Treat as a security incident (docs/SECURITY.md): take screenshots, suspend the affected shops from the admin, check the Activity logs, then fix |
| Someone lost their phone and recovery codes | A shop's owner can reset staff who work only for that shop (Settings › Staff). Otherwise, after checking who they are (call back on the shop's number on file, and ask something only the shop knows, such as its last invoice amount), open the shop in the admin and press **Reset 2FA** by their name: they're signed out, emailed, and it's in the shop's Activity with your email |
| Someone's account compromised | Reset their password (sessions end), turn off their access in Staff, check Activity for what they did |
| Replica behind or unreachable | Admin Database page, "Read replica". Reports and exports read from it, so they fail or show old numbers; tills and everything else don't. `bin/kamal accessory logs db-replica -d scaled`. To take it out of service, remove `DATABASE_REPLICA_HOST` and redeploy: reads go back to the primary |

## 6. Scaling out

One VPS carries dozens of shops. Signs it's time to grow: CPU busy through trading hours, the admin
Database page showing cache hits below 99% with no more memory to give, or reports and exports
slowing the tills. Grow in this order, one step at a time, each with a quiet evening and a backup
taken just before.

**The target** (`config/deploy.scaled.yml`, a Kamal destination merged over `config/deploy.yml`):

| Server | Runs | Reachable from |
|---|---|---|
| web-1, web-2 | Puma behind kamal-proxy | Cloudflare (80/443), private network |
| jobs | Solid Queue (`bin/jobs`): webhooks, SMS, eTIMS, exports, billing | private network only |
| db | PostgreSQL primary: every write, the tills, the live dashboard | private network only |
| db-replica | streaming replica: reports and data exports | private network only |

All on Contabo's private networking in one region (10.0.0.0/24 in the file; use your own addresses),
`ufw` allowing 5432 only from that network. Uploads move to S3-compatible object storage (Contabo
Object Storage in the same region), because two web servers can't share a disk.

1. **Database on its own server.** Provision it like section 1, with more memory, and re-run pgtune
   for its size into `config/postgres/postgresql.conf`. Add `REPLICATION_PASSWORD` to `.kamal/secrets`.
   Then `bin/kamal accessory boot db -d scaled` (its first-boot script also creates the `replicator`
   role and allows it in `pg_hba.conf`). Then, after closing time (tills keep selling offline if
   anyone is still trading): `bin/kamal app stop`, take a final dump from the old server (section 2),
   restore it on the new one (section 3), deploy with `-d scaled`, and check `/up` and a test sale.
2. **Read replica.** `bin/kamal accessory boot db-replica -d scaled`. On first start
   `config/postgres/start_replica.sh` clones the primary with `pg_basebackup` through a replication
   slot and starts as a hot standby. The admin Database page shows it streaming with its lag. With
   `DATABASE_REPLICA_HOST` set (it is in the scaled file), reports and exports read from it.
   Row-level security applies there too: `Account.reading` sets the shop on the replica's own
   connection, and a replica connection without one sees nothing.
3. **Uploads to object storage.** Create the bucket (private) and an access key; add the key to
   `.kamal/secrets` and the endpoint and bucket to `config/deploy.scaled.yml`. Deploy, then move the
   existing files: `bin/kamal app exec -d scaled "bin/rails storage:copy[local,object_storage]"`
   (safe to run again). Add the bucket to the off-site backup (section 2).
4. **Jobs on their own server.** Already in the scaled file: `SOLID_QUEUE_IN_PUMA: false` on the web
   servers and a `job` role running `bin/jobs`. Check the queue drains after deploying:
   `bin/kamal console -d scaled`, then `SolidQueue::Job.where(finished_at: nil).count`.
5. **A second web server.** Both run the same image; point Cloudflare at both (a Load Balancer
   pool with the `/up` health check, or two proxied A records). Sessions live in cookies and rate
   limits in the database's cache, so a till can land on either.

**Connection budget:** a Puma thread holds at most one connection per database, so each web server
uses up to `WEB_CONCURRENCY × RAILS_MAX_THREADS × 4` (app, cache, queue, cable: 6 × 3 × 4 = 72), and
the job server `JOB_CONCURRENCY × (JOB_THREADS + 2) × 3` plus a few (about 50). Two web servers and a
job server come to about 195, against `max_connections = 250` (the sums are in
`config/postgres/postgresql.conf`). Each process's pool is sized in `config/database.yml` to the larger
of its Puma threads and its job threads + 2 (Solid Queue's heartbeat and poller need their own);
`DB_POOL` overrides it. A "could not obtain a connection from the pool" error means a pool is short
for its threads; "too many connections" means the server's budget is spent. At
four web servers, put PgBouncer (transaction pooling) in front of the primary, and move the
row-level security settings to `SET LOCAL` inside each transaction first: session-level settings
don't survive transaction pooling.

**Going back:** every step reverses by deploying without `-d scaled` (or removing one setting):
without `DATABASE_REPLICA_HOST` reads return to the primary; without `ACTIVE_STORAGE_SERVICE` uploads
go to local disk again (copy them back with `storage:copy[object_storage,local]` first).

**Trying a replica locally:** clone your development database into a standby and point the
development replica at it:

```sh
sudo -u postgres pg_basebackup -D /var/lib/postgresql/hp_replica -R -X stream -c fast
sudo -u postgres cp /etc/postgresql/16/main/pg_{hba,ident}.conf /var/lib/postgresql/hp_replica/
echo "port = 5433" | sudo -u postgres tee /var/lib/postgresql/hp_replica/postgresql.conf
sudo -u postgres /usr/lib/postgresql/16/bin/pg_ctl -D /var/lib/postgresql/hp_replica -l /tmp/replica.log start
DATABASE_REPLICA_PORT=5433 bin/dev
```
