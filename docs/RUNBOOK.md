# HardPoint runbook

How to run HardPoint in production: first setup, backups, disaster recovery, routine care, the common
incidents, alerts, staging and deploying. Everything starts on one Contabo VPS behind Cloudflare, deployed
with Kamal (`config/deploy.yml`); the database is the Kamal `db` accessory (PostgreSQL 18). Section 6 covers
growing onto several servers.

## Targets

| | Target | How |
|---|---|---|
| **RPO** (data that can be lost) | **5 minutes** | Every WAL segment is archived and shipped off-site within a minute of being finished, and a segment is finished at least every 5 minutes (`archive_timeout`); hourly encrypted dumps as the simple fallback; files daily |
| **RTO** (time to be selling again) | **30 minutes** with a standby, **2 hours** from backups | Promote the replica (`config/postgres/promote_replica.sh`) and redeploy; or a fresh VPS, Kamal setup and `restore_pitr.sh latest` |
| Tills during an outage | keep selling | The offline till (Phase 8) takes cash and typed M-Pesa codes and sends the sales when the server is back |
| **Knowing it's broken** | within 10 minutes | Unhandled errors go to Sentry or the operators' inbox at once; `PlatformHealthJob` checks the platform every 10 minutes and the uptime monitor watches `/health` from outside (section 7) |

## 1. First setup

1. **VPS** (Ubuntu 24.04, Cloud VPS 20 or bigger): a non-root deploy user with SSH keys only, root and
   password logins off; `ufw` allowing 22 from your address and 80/443 only from
   [Cloudflare's ranges](https://www.cloudflare.com/ips/); `fail2ban`, `unattended-upgrades`, a 4 GB
   swap file, time sync; Docker. Turn on Contabo's snapshot for the disk as an extra safety net.
2. **Cloudflare:** `hardpoint.app` and `*.hardpoint.app` proxied to the VPS; SSL **Full (strict)** with an
   Origin CA certificate for both (its PEM files go in `.kamal/secrets`); WAF managed rules; a rate
   limiting rule on `POST /session`; caching for `/assets/*`.
3. **Email (AWS SES):** in the SES console pick a region (eu-west-1 is close enough; af-south-1 if the
   account has it) and create an IAM user with `ses:SendEmail`, `ses:Get*`, `ses:Put*`,
   `ses:Create*`, `ses:Update*`, `ses:DeleteSuppressedDestination`, `sns:CreateTopic` and
   `sns:Subscribe`. Add its key with `bin/rails credentials:edit` under `ses: { region:, access_key_id:,
   secret_access_key:, configuration_set: hardpoint }`, deploy, then run
   `bin/kamal app exec "bin/rails ses:setup"`: it verifies the sending domain (the domain of
   `MAILER_FROM`), sets a custom MAIL FROM, switches on the account suppression list, makes the
   configuration set and an SNS topic that delivers bounces, complaints and rejections to
   `/webhooks/ses` (the app confirms the subscription itself), and prints the DNS records to add at
   Cloudflare (DNS only, not proxied): three DKIM CNAMEs, an MX and SPF TXT for `mail.<domain>`, and a
   DMARC TXT. Put the printed topic ARN in the credentials as `ses.sns_topic_arn`. Then request
   production access in the SES console (the sandbox only sends to verified addresses) and send a test
   of every mailer (`bin/rails runner` or the mailer previews). `bin/rails ses:status` shows when every
   record has been picked up; the admin **Email** page shows the account's standing from then on.
4. **Secrets:** `RAILS_MASTER_KEY`, `POSTGRES_PASSWORD`, `HARDPOINT_DATABASE_PASSWORD` and the origin
   certificate in the environment `.kamal/secrets` reads. Run `bin/rails db:encryption:init` once and
   store the keys in credentials. Keep a copy of the master key and the backup passphrase in the team
   password manager: **without them, backups can't be read**.
5. **Deploy:** `bin/kamal setup` (boots Postgres with `config/postgres/postgresql.conf` and its first-boot
   script, which creates the app role, the database and `pg_stat_statements`), then `bin/kamal deploy`.
6. **Integrations and billing:** see the README's Deployment section (M-Pesa, eTIMS, SMS, Paystack).
7. **Backups:** section 2. Then do the drill in section 3 before the first shop signs up.

## 2. Backups

Two kinds, both on the VPS host (not in a container), both encrypted with AES-256 under
`BACKUP_PASSPHRASE` and uploaded to an S3-compatible bucket in another region or provider (Contabo
Object Storage, Backblaze B2):

- **Continuous:** Postgres archives every finished WAL segment into the data volume's `wal_archive`
  directory (`archive_mode`, `archive_timeout = 300` in `config/postgres/postgresql.conf`), and
  `config/backup/wal_ship.sh` runs every minute from cron to encrypt and upload them to `wal/`. A
  weekly `backup.sh base` takes a physical copy of the cluster (`pg_basebackup`) to `base/`. Together
  they restore the cluster to any minute (`restore_pitr.sh`, section 3); this is what gives the 5-minute RPO.
- **Hourly dumps:** `backup.sh db` dumps the app and job databases with `pg_dump` to `hourly/` (and
  `daily/`). Simpler to restore one database from, independent of the WAL machinery, and what the
  staging refresh and the restore drill use. Uploaded files (Active Storage) are backed up daily by
  `backup.sh files`.

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
ENV
sudo chmod 600 /etc/hardpoint/backup.env
sudo tee /etc/cron.d/hardpoint-backup > /dev/null <<'CRON'
*  * * * * root /opt/hardpoint/wal_ship.sh     >> /var/log/hardpoint-wal.log 2>&1
17 * * * * root /opt/hardpoint/backup.sh db    >> /var/log/hardpoint-backup.log 2>&1
47 1 * * * root /opt/hardpoint/backup.sh files >> /var/log/hardpoint-backup.log 2>&1
37 2 * * 0 root /opt/hardpoint/backup.sh base  >> /var/log/hardpoint-backup.log 2>&1
CRON
```

Add `WAL_HEARTBEAT_URL=https://hc-ping.com/...` to `backup.env` as a second heartbeat, expected every
few minutes: `wal_ship.sh` only pings it when nothing is left unshipped, so silence means the archive is
falling behind (the log says why). Bucket lifecycle rules: delete `hourly/` after 2 days, `daily/` and
`files/` after 35 days, and `wal/` and `base/` after 35 days (a base backup is only useful with the
WAL that follows it, and there's one a week). Use a bucket key that can write but not delete, so a
compromised server can't wipe its own backups (lifecycle rules do the deleting). The last 48 hours of
dumps also stay in `/var/backups/hardpoint` on the VPS.

The backup heartbeat check should expect a ping every hour; if one is missed, check
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
monthly** and after any change to the database setup: the staging refresh (section 8) restores the
newest dump every time it runs, and once a quarter do a point-in-time restore onto a scratch VPS too.
Note the time taken below.

With a standby database (section 6), losing the primary isn't a restore at all: run
`config/postgres/promote_replica.sh` and redeploy (about 30 minutes, "Losing the primary" in section 6).
Without one:

1. **New VPS**, set up as in section 1 steps 1 and 5 (`bin/kamal setup` with the same secrets; point
   `servers` and the accessory `host` in `config/deploy.yml` at the new address). Stop the app while
   restoring: `bin/kamal app stop`.
2. **Restore the database.** To the last shipped WAL segment, about five minutes before the failure:
   ```sh
   /opt/hardpoint/restore_pitr.sh latest
   ```
   It fetches the newest weekly base backup and every WAL segment after it, unpacks them into the
   `hardpoint-db` container's data volume (the old data directory is moved aside, not deleted), and
   starts Postgres in recovery; Postgres replays to the end and promotes itself. The same script
   with a time (`"2026-11-08 10:42:00+03"`) restores to just before a bad migration or a mistaken
   bulk change. If the WAL archive is unusable, fall back to the newest hourly dump:
   ```sh
   /opt/hardpoint/restore.sh s3:hourly/hardpoint-db-<newest>.tar.enc
   ```
   which checks the checksum, decrypts, recreates roles and restores `hardpoint_production` and
   `hardpoint_production_queue` into empty databases (the cache and cable databases rebuild
   themselves); it refuses to restore over a database that already has tables.
3. **Restore files:** fetch the newest `files/` backup, then
   `openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:BACKUP_PASSPHRASE < FILE | sudo tar -C /var/lib/docker/volumes/hardpoint_storage/_data -xzf -`.
4. **Start and check:** `bin/kamal app boot`; `bin/rails db:migrate:status` via `bin/kamal console`
   shows nothing pending; sign in to a shop, open the till, look at today's sales; the admin
   Database page shows sensible sizes.
5. **Cloudflare:** change the two DNS records to the new address (proxied, so it takes effect in
   seconds).
6. **Tills** that sold offline send their sales by themselves once they can reach the server. Sales
   made online in the last few minutes before the outage (after the last shipped WAL segment) are
   lost: tell the affected shops (Activity shows what arrived), and they can re-enter them from
   their paper receipts.
7. **Backups from the new server:** install the cron lines from section 2 and take a base backup
   straight away (`backup.sh base`), so the archive has a starting point again.

### Drill log

| Date | Where | Backup | Restore | Checks |
|---|---|---|---|---|
| 2026-09-24 | Local container, PostgreSQL 16, 25 MB database | 0.4 s | 0.9 s | Row counts of all 66 tables identical; RLS enabled and forced on 56 tables with 56 policies; all tables owned by the app role; 273 indexes; as the app role one shop sees its 310 sales and no shop sees none; the app boots against the copy and runs reports |

Restoring grows roughly with the database size (about a minute per gigabyte on NVMe is a fair first
guess); time it on the real server at the first drill and adjust the RTO if needed.

## 4. Routine care

- **Daily:** glance at the alerts inbox (or Sentry) and the platform checks at the top of the admin
  **Database** page; anything red there is also what `/health` tells the uptime monitor.
- **Weekly:** merge Dependabot's pull requests once CI is green (it runs Brakeman, bundler-audit and
  importmap audit weekly even without commits); deploy to staging, then production (section 9).
- **Monthly:** the restore drill (section 3): refresh staging from the newest dump (section 8), and
  rehearse promoting the replica where there is one; look at the admin **Database** page: cache hit
  rates below 99% mean Postgres wants more memory, "Dead rows" much higher than live rows means
  vacuum is behind, and the slowest queries show where to add an index; check the VPS disk (`df -h`)
  and the backup bucket's size.
- **Every 3 months:** rotate the Paystack, M-Pesa and SMS API keys and the SES SMTP password; review
  who has platform admin (`User.where(admin: true)`) and glance down the admin **Audit** page.
- **Yearly:** renew the Cloudflare Origin CA certificate before it expires (15-year certificates avoid
  this); re-run pgtune if the VPS size changed.

## 5. Incidents

| Symptom | First steps |
|---|---|
| Site down | `bin/kamal app details`, `bin/kamal logs`; `curl -I https://hardpoint.app/up` and `https://hardpoint.app/health?token=…` (which check is failing). Tills keep selling offline meanwhile. |
| An alert email, or Sentry | The subject names the check or the error; the body has the details and the other checks. The first alert is sent straight away, then a "Still happening" reminder at most once a day while it lasts; a platform check that passes again sends "All clear". Failed jobs: `bin/kamal console`, `SolidQueue::FailedExecution.last(5).map(&:error)`, then `.retry` on each once the cause is fixed. |
| WAL heartbeat silent | `/var/log/hardpoint-wal.log` on the host: the store refused an upload, or the data volume moved. Segments wait in `wal_archive` and go when it works again; Postgres keeps running regardless (the archive copy is local). |
| "could not obtain a connection" / "too many connections" | Pool too small for its threads, or Postgres' `max_connections` spent: see the connection budget in section 6 before raising either |
| Slow | Admin Database page: long-running queries and connections; `bin/kamal accessory logs db` for slow-query lines (over 500 ms are logged); raise `WEB_CONCURRENCY` if CPU is spare |
| Database full or disk full | `df -h`; old local backups are in `/var/backups/hardpoint`; `docker system prune` for old images |
| Emails not arriving | Admin **Email** page: is SES sending enabled, still in the sandbox, reputation healthy, quota left? Is the address on the suppression list (lift it there once it works)? `bin/rails ses:status` for the domain's DKIM and MAIL FROM. SES's own console for sending statistics. |
| SES paused sending, or reputation not healthy | Bounces or complaints went past Amazon's limits. The admin Email page lists what bounced and complained; stop whatever mailer caused it (a bad import of customer emails, a shop texting receipts to typed addresses), lift nothing until it's fixed, then ask SES to review in the console. The `email` platform check alerts on this. |
| M-Pesa payments not arriving | Shop's Settings › M-Pesa "Test connection"; Safaricom's callback IP list (`MPESA_CALLBACK_IPS`) |
| eTIMS queue growing | Settings › KRA eTIMS › Submissions shows the errors; KRA outages retry by themselves |
| A shop reports seeing another shop's data | Treat as a security incident (docs/SECURITY.md): take screenshots, suspend the affected shops from the admin, check the Activity logs, then fix |
| Someone lost their phone and recovery codes | A shop's owner can reset staff who work only for that shop (Settings › Staff). Otherwise, after checking who they are (call back on the shop's number on file, and ask something only the shop knows, such as its last invoice amount), open the shop in the admin and press **Reset 2FA** by their name: they're signed out, emailed, and it's in the shop's Activity with your email |
| A new platform administrator, or one who lost their phone | Make them an admin (`User#update!(admin: true)` in the console); for a lost phone, `user.disable_two_factor` first. Then `bin/kamal app exec 'bin/rails "admin:enrolment_link[their@email]"'` prints a link that works once, for a day: send it privately. They open it, sign in with their password and scan the QR code. Their password alone never lets anyone set two-factor up |
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

**Losing the primary:** with the replica streaming, failover is a promotion, not a restore.
`config/postgres/promote_replica.sh 10.0.0.22` promotes the replica's Postgres (it accepts writes from
then on) and tells you the two lines to change in `config/deploy.scaled.yml` (`DATABASE_HOST` to the
promoted server, `DATABASE_REPLICA_HOST` removed) before `bin/kamal deploy -d scaled`. Install the WAL
shipping cron on the promoted server and take a base backup. Build a new replica from it afterwards
(step 2) and put `DATABASE_REPLICA_HOST` back. Rehearse this at the monthly drill, on staging or on a
scratch pair: it should take under 30 minutes end to end, which is the RTO in the targets.

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

## 7. Alerts and monitoring

Somebody is told within minutes when something breaks, in three layers:

1. **Errors, as they happen.** Every unhandled exception in a request or a job, every job that gives up
   (`after_discard` in `ApplicationJob`), every failed recurring task and everything the app reports
   with `Rails.error` goes to **Sentry** when `SENTRY_DSN` is set (`config/initializers/sentry.rb`; no
   request bodies, cookies or addresses are sent). Without Sentry, `Alerts::ErrorSubscriber` emails
   the same things to `ALERTS_EMAIL` (default: the support address): the first straight away, then at
   most one "Still happening" reminder a day (with a count) per error
   class and place, with the backtrace (`config/initializers/error_reporting.rb`).
2. **Platform checks, every 10 minutes.** `PlatformHealthJob` runs `PlatformHealth`: the primary
   answers; the replica is streaming and under a minute behind; Solid Queue has a live worker,
   dispatcher and scheduler; no job has waited more than 15 minutes; no job failed in the last hour;
   no shop has a sale waiting more than 2 hours for KRA; no shop backup failed in the last day or has
   run for more than 3 hours; SES will still send for us (not paused, reputation healthy, under 80% of
   today's quota, no spam complaints in the last day); the disk is under 80% (warning) or 90% (failing). A failing check is
   emailed (reminded the same way), with an "All clear" when it passes again. The same checks are the **Platform checks** panel at the top of
   the admin Database page.
3. **From outside.** `GET /health` (any host, no sign-in) answers 200 while every check passes and 503
   when one fails, with the checks' names; with `?token=HEALTH_TOKEN` it includes the details. Point
   the uptime monitor (Better Stack, UptimeRobot, Cloudflare health checks) at
   `https://hardpoint.app/health` and at one shop's sign-in page every minute, alerting by SMS and
   phone, and publish its status page from the help centre. The backup and WAL heartbeats
   (section 2) are the fourth signal: silence from either means backups have stopped.

Set `SENTRY_DSN`, `ALERTS_EMAIL` and `HEALTH_TOKEN` in `config/deploy.yml` / `.kamal/secrets`. Alert
emails are sent straight away over SMTP, not through the job queue, so the queue being down is
something they can tell you about.

## 8. Staging

`config/deploy.staging.yml` is a Kamal destination for one small VPS at `staging.hardpoint.app`, with
shops at `acme.staging.hardpoint.app` (`APP_TLD_LENGTH=2`). It runs the production image with
`HARDPOINT_ENVIRONMENT=staging`, which: sends every email to `STAGING_MAIL_TO` instead of real owners
and customers (the real recipients go in the subject), keeps texts in the outbox, adds a `noindex`
header and a yellow banner on every page, labels alerts and Sentry events "staging", and allows the
M-Pesa, Airtel and eTIMS simulators. It needs its own Cloudflare Origin CA certificate (two lines in
`.kamal/secrets`) and the two DNS records.

```sh
bin/kamal setup -d staging     # first time
bin/kamal deploy -d staging    # every release goes here first, then to production
```

**Refreshing it from production:** on the staging host, with `/etc/hardpoint/backup.env` holding a
read key for the backup bucket and the passphrase,
`STAGING_PASSWORD=... /opt/hardpoint/refresh_staging.sh` fetches the newest hourly dump, restores it
(stopping the app meanwhile), runs any pending migrations, and runs `bin/rails staging:anonymise`,
which scrambles every customer, supplier, staff member and payer, removes API keys and webhooks,
turns every M-Pesa, Airtel and eTIMS connection into a simulator, switches texts and shop backups
off, and sets every password to `STAGING_PASSWORD` (two-factor off). The task refuses to run anywhere
but staging. Do this monthly as the restore drill, and before a penetration or load test.

## 9. Deploying

- **Staging first**, watch for an hour, then production. `bin/kamal rollback <version>` is the way back.
- **Migrations run once per deploy** from the deploying machine: `.kamal/hooks/pre-deploy` runs
  `bin/rails db:migrate` in a throwaway container of the new version on the primary host, before any
  container of that version boots, so two web servers can't race and a failing migration stops the
  deploy. Containers themselves don't migrate (`bin/docker-entrypoint` only creates the databases on
  a brand-new server, or when `MIGRATE_ON_BOOT=true`).
- **Migrations must be safe for the version still running** during the deploy: `strong_migrations`
  refuses the usual mistakes (dropping or renaming a column in one step, an index without
  `CONCURRENTLY`, a backfill in the same transaction, an `execute` it can't read) and explains the
  two-step way; `safety_assured { }` is for the cases you've thought about. New tenant tables still
  need `enable_row_level_security` and deferrable foreign keys (README). Deploy a migration that
  rewrites a table the tills write to (`sales`, `sale_lines`, `stock_movements`) in the maintenance
  window, 02:00–04:00 EAT, announced in the admin the day before.
