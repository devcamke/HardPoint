# Packaging, selling and running HardPoint as a service

How to turn the HardPoint code into a product shops pay for and can rely on: what to sell and at what
price, how to find the first customers, and what the platform needs so that it stays up, keeps data
safe, and recovers when something breaks. It builds on what is already in the repository: the launch
checklist ([LAUNCH.md](LAUNCH.md)), the runbook ([RUNBOOK.md](RUNBOOK.md)), the security review
([SECURITY.md](SECURITY.md)) and the load tests ([../perf/README.md](../perf/README.md)).

**Contents:** [Where it stands](#1-where-it-stands) · [What to sell](#2-what-to-sell) ·
[How to sell it](#3-how-to-sell-it) · [Targets to promise](#4-targets-to-promise) ·
[Redundancy](#5-redundancy) · [Security](#6-security) · [Reliability](#7-reliability) ·
[Availability and support](#8-availability-and-support) · [What it costs to run](#9-what-it-costs-to-run) ·
[Order of work](#10-order-of-work)

## 1. Where it stands

The product is unusually complete for a pre-launch SaaS. Judged against what a buyer and an auditor
would ask for:

| Area | State | Evidence |
|---|---|---|
| Feature scope | Full till, stock, purchasing, credit customers, M-Pesa, eTIMS, reports, API, online store | README, FEATURES.md |
| Multi-tenancy | Postgres row-level security on all 56 tenant tables, forced; cross-tenant sweep over 146 routes in CI | SECURITY.md, `test/integration/tenant_isolation_sweep_test.rb` |
| Billing | Trial → plan → monthly/yearly invoices by M-Pesa or card; read-only lock on overdue; add-ons; one-off invoices | `app/models/plan.rb`, `app/models/billing` |
| Offline | Till keeps selling from IndexedDB, sales replay idempotently by UUID | `app/models/sale/offline.rb`, `app/javascript/offline` |
| Backups | Hourly encrypted dumps off-site with a heartbeat; per-shop verified backups owners can download | `config/backup`, `AccountBackup` |
| Scaling | Kamal destination for 2 web + jobs + primary + streaming replica, connection budget worked out | `config/deploy.scaled.yml`, RUNBOOK §6 |
| Performance | 40 flat-out cashiers on 4 cores, p95 scan 278 ms; headroom of roughly 10× real tills | perf/README.md |
| Security review | Internal review done and fixed; penetration test brief written, test not yet done | SECURITY.md |

What is **not** there yet, and matters for selling:

1. **Nobody is told when it breaks.** `Rails.error` has no subscriber, there is no uptime check and
   no alert on a failed job. This is the single biggest gap between "works" and "sellable".
2. **One server, one copy.** Production is one VPS with the database beside the app. A disk failure
   means a 2-hour rebuild and up to an hour of lost sales (RUNBOOK targets). Fine for a pilot, not
   for a shop paying KES 15,000 a month.
3. **No staging.** Every deploy goes straight to the only environment.
4. **Open security items:** sessions never expire, one QZ Tray key for all shops, Airtel callbacks
   not restricted by address, no external penetration test.
5. **No paper:** terms of service, privacy notice, data processing terms and a service level
   agreement don't exist yet; the ODPC registration isn't done.
6. **Migrations run inside the container entrypoint** (`bin/docker-entrypoint` runs `db:prepare`), so
   two web servers starting together would both try to migrate.

Everything below is about closing those six gaps in the right order while starting to sell.

## 2. What to sell

### Sell the service, not the software

Keep HardPoint as a hosted subscription at `shop.hardpoint.app`. Do not offer on-premise installs,
even when a shop asks: a copy running on a shop's own PC has no backups you control, no updates, no
eTIMS certificate management, and every support call becomes a site visit. The offline till already
answers the real worry behind "we want it on our own computer", which is "what happens when the
internet is down". Say that in the pitch.

The Docker image does make a **dedicated instance** possible later (one shop, its own database and
subdomain, same code) as an Enterprise extra at several times the shared price. Keep it in reserve
for a chain that insists; do not build it until one has signed.

### The plans, and what to adjust

The current plans are sound and already match how hardware shops grow. Keep the shape and tune a few things:

| | Starter | Business | Enterprise |
|---|---|---|---|
| Price / month | KES 2,500 | KES 6,500 | KES 15,000 |
| Branches / tills / logins | 1 / 2 / 3 | 3 / 8 / 15 | unlimited |
| Add-on till / branch | 750 / 2,000 | 500 / 1,500 | — |
| API and webhooks | — | yes | yes |
| Yearly | 10 months | 10 months | 10 months |

Recommendations:

- **Make the differences about reliability and support as well as limits.** Shops cannot judge a
  till limit, but they understand "someone answers the phone when the till is down". Put support
  hours and response times on the pricing page per plan (see §8), and the per-shop backup schedule
  (Starter weekly, Business daily, Enterprise daily plus on demand). The backup schedule is already a
  per-shop setting; tie it to the plan.
- **Price the Starter plan against what it replaces**: a receipt book, a KRA-registered ETR device
  and the time to type sales into a spreadsheet. KES 2,500 is below the cost of a monthly ETR
  service contract for many shops; say so.
- **Bill yearly by default for Business and Enterprise** at signup, with a monthly option, not the
  other way round. Yearly payments fund the infrastructure in §5 before many shops exist and halve
  the churn work.
- **Keep products unlimited** (already the case). It is the one limit competitors impose that
  hardware shops hate, and it costs you nothing.
- **Enterprise should carry a named onboarding engineer and a data processing agreement** (§6). That
  is what justifies the gap between 6,500 and 15,000, not the absence of limits.

### Packaged services around the subscription

These are already modelled as one-off invoices from the admin (`Plan::SETUP_CENTS`). Make them
explicit products with fixed prices on the pricing page:

| Package | What's in it | Suggested price (KES) |
|---|---|---|
| **Remote setup** | Import of the shop's product list from a spreadsheet, tills and printers configured over a call, staff and PINs, M-Pesa and eTIMS connected, 1 hour of training by video | from 15,000 (today's `SETUP_CENTS`) |
| **On-site setup** | Same, done in the shop over a day, plus watching the first hour of selling | from 35,000 plus travel outside Nairobi |
| **Till kit** | Barcode scanner, 80 mm receipt printer, cash drawer; optionally a touch POS terminal; tested with QZ Tray before shipping | at cost plus 20–25%, quoted |
| **Data migration** | From an existing POS (export → clean → import, stock opening balances, customer balances) | from 25,000 |
| **eTIMS certification support** | Registering OSCU devices per branch, sandbox tests, go-live | included in setup; standalone from 10,000 |

Setup fees do two things: they pay for the most expensive part of the relationship (the first week),
and they signal that a trial is not the same as onboarding. Waive the fee for pilot shops and for
yearly plans paid up front; never for monthly Starter.

### Paperwork to package with the product

None of this exists yet and all of it is needed before the first invoice:

1. **Terms of service** (subscription, payment, suspension, data return on closure, liability cap at
   fees paid in the last 12 months).
2. **Privacy notice** under the Kenya Data Protection Act, 2019, and **registration with the Office
   of the Data Protection Commissioner** as a data processor (for shops' customer data) and
   controller (for shop owners' and staff accounts). LAUNCH.md already lists this; do it first, it takes weeks.
3. **Data processing terms** that every shop agrees to at signup, saying what HardPoint does with
   customers' names, phone numbers and KRA PINs, where it is stored, and the 72-hour breach notice.
4. **Service level agreement** for Business and Enterprise (§8).
5. **An acceptable-use clause** covering the API and the online store.

Have a Kenyan lawyer review these; a day of their time is cheaper than one dispute.

## 3. How to sell it

The LAUNCH.md pilot plan is right: 2–3 different shops, free, four weeks, weekly visits. What to do around it:

**Who buys.** The owner, usually on the premises, who fears theft at the till and KRA penalties more
than they want reports. The pitch order that follows from that: (1) every sale signed with KRA so
eTIMS is handled, (2) a shift close that shows what cash should be in the drawer, (3) M-Pesa on the
receipt with no typing, (4) the till keeps working when Safaricom's internet drops, (5) they can see
today's sales on their phone from home. Reports and the API come last.

**Where to find them.** Hardware shops cluster: Nairobi's Kirinyaga Road and Industrial Area,
Mombasa Road, and the trading centres of every county town. Field selling with a till kit in a bag
works better than ads. Three channels worth setting up in the first six months:

- **Till-hardware vendors** (the shops selling scanners and printers) as resellers for a 15–20%
  first-year commission: they already meet every shop buying a till.
- **Accountants and KRA tax agents** who serve small traders: a referral fee, and the QuickBooks
  export and VAT report as their reason to recommend it.
- **Suppliers and distributors** (cement, paint, steel) whose sales reps visit hundreds of hardware
  shops: co-branded "order from your HardPoint" once the purchasing API is used by one of them.

**Proof.** Keep the public demo shop (`ALLOW_INTEGRATION_SIMULATORS` for the demo only), a
five-minute video of a sale with M-Pesa and an eTIMS receipt, and one-page case notes from each pilot
shop with their numbers (time per sale, cash variance before and after). The help centre and
USER_GUIDE.md are already better than most competitors' documentation; link to them from the sales page.

**Conversion.** The 30-day trial converts when the shop has imported its products and done a real
day of sales. Measure, per trial: products imported (yes/no), tills opened, first real sale, M-Pesa
connected, eTIMS connected. Call every trial that hasn't imported products by day 3 and offer the
remote setup package. Trials that don't sell in week one almost never convert; stop chasing them.

**Numbers to watch monthly:** trials started, trials with a real sale, paid conversions, monthly
recurring revenue, churn (shops that go read-only and don't pay within 7 days), support tickets per
shop, till-down incidents, and the gross margin after the hosting costs in §9.

## 4. Targets to promise

Decide these before building the redundancy, because they decide how much of it is needed.

| Measure | Pilot (now) | Launch (Business/Enterprise SLA) | Later |
|---|---|---|---|
| **Availability** of the web app and API, measured monthly at `/up` and a shop sign-in page, excluding announced maintenance | best effort | **99.9%** (about 44 minutes down a month) | 99.95% |
| **RPO** (sales that can be lost from the server) | 1 hour (hourly dumps) | **5 minutes** (continuous WAL archiving) | seconds (synchronous standby) |
| **RTO** (time to be back after losing the server) | 2 hours (rebuild from dump) | **30 minutes** (promote the standby) | minutes (automatic failover) |
| **Till during an outage** | keeps selling offline | keeps selling offline | same |
| **Support response, till down** | WhatsApp, best effort | Business 2 hours, Enterprise 1 hour, during shop hours | 24/7 for Enterprise |

Why these: 99.9% is what one well-run region with a standby can honestly deliver; promising 99.99%
means a second region and is not worth it while the offline till covers short outages. The RPO
matters more than the RTO for a till: a shop forgives an hour of offline selling far more easily than
losing an hour of sales it already made.

The offline till is the real availability feature and the strongest thing in the pitch. Make sure it
is true under the SLA's conditions: a till that has opened once online, selling cash and typed M-Pesa
codes, replaying when the server returns. Test it in the pilot by pulling the shop's internet for an
hour on purpose.

## 5. Redundancy

Grow in stages. Each stage is a complete, consistent setup; do not half-do one.

### Stage 0, the pilot: one VPS done properly

What exists in `config/deploy.yml` plus the hardening in RUNBOOK §1. Add before the first pilot shop:

- **Error reporting and alerts** (§7). Without them you don't know whether you met any target.
- **Continuous WAL archiving to object storage** alongside the hourly dumps. Use pgBackRest or WAL-G
  in a sidecar container pointed at the `hardpoint-db` data directory, archiving to a bucket in a
  different provider or region from the VPS. This takes the RPO from an hour to minutes with no
  second server, and gives point-in-time recovery (restore to 10:42 before a bad migration, not to
  the last dump). Keep the hourly dumps too: they are simpler to restore and independent of the tool.
- **A separate, write-only backup bucket** and lifecycle deletes (already in the runbook).
- **Key escrow:** `RAILS_MASTER_KEY`, the Active Record encryption keys and `BACKUP_PASSPHRASE` in a
  password manager shared with a second person. If these are lost the backups are unreadable;
  this is the most likely total-loss scenario for a one-person company, not a disk failure.
- **Provider snapshots** of the VPS disk daily (Contabo offers this) as a last resort.

### Stage 1, launch: a standby database and a second web server

The target already described in RUNBOOK §6 and `config/deploy.scaled.yml`, with two changes:

1. **Make the replica a failover candidate, not just a reporting replica.** The streaming replica
   in the scaled config exists for reports. Write the promotion runbook now: `pg_ctl promote` on the
   standby, point `DATABASE_HOST` at it, redeploy, re-point the old primary as the new standby.
   Rehearse it at the monthly drill. That gives a 30-minute RTO with the tools already in place.
   Automatic failover (Patroni, pg_auto_failover) adds operational weight that isn't worth it below
   a few hundred shops; a well-rehearsed manual promotion is more reliable than an automated one
   nobody has watched work.
2. **Or buy the database.** A managed PostgreSQL with built-in high availability and point-in-time
   recovery (from a cloud provider with a region in or near Africa, or a Postgres specialist) replaces
   steps 1 and 2 of the scale-out and the WAL archiving. It costs more per month than a VPS but
   removes the task most likely to go wrong under pressure. Check three things before choosing one:
   it must support `pg_stat_statements` and a non-superuser app role (row-level security depends on
   it), PostgreSQL 18, and connection counts of 250 or a pooler that supports session settings
   (`SET app.current_account_id`) or the `SET LOCAL` change noted in RUNBOOK §6.

Either way, at Stage 1:

- **Two web servers** behind Cloudflare, both with kamal-proxy and the `/up` health check. Sessions
  are cookies and rate limits live in the database cache, so no sticky sessions are needed (already true).
- **A separate jobs server** running `bin/jobs` so an export or a backup never slows a till
  (already in the scaled file). Solid Queue's recurring tasks run from one dispatcher; keep it to one
  jobs server, or configure a single dispatcher, so the daily billing and eTIMS retries don't double.
- **Uploads in object storage** (`ACTIVE_STORAGE_SERVICE=object_storage`), shop backups in a
  different bucket and region (`BACKUP_STORAGE_SERVICE=backups`).
- **Migrations as a deploy step, not in the entrypoint.** Move `db:prepare` out of
  `bin/docker-entrypoint` into a Kamal `pre-deploy` hook (or `kamal app exec --reuse bin/rails
  db:migrate` before boot). Add the `strong_migrations` gem so a migration that would lock a hot
  table during trading is refused in development. `lock_timeout = 10s` in `postgresql.conf` is the
  safety net, not the plan.
- **A staging server**, one small VPS running the same image against a copy of production restored
  from last night's backup (which doubles as the restore drill). Every release goes there first.

### Stage 2, growth: a second region and a pooler

Not before several hundred shops or a signed chain contract:

- PgBouncer in transaction mode in front of the primary, after moving row-level security to `SET LOCAL`
  inside the transaction (noted in RUNBOOK §6).
- A warm standby in a second region or provider (asynchronous replication) for region loss.
- Cloudflare Load Balancer with origin pools and automatic failover between regions.

### Dependencies you cannot make redundant, and what to do instead

| Dependency | If it fails | Mitigation |
|---|---|---|
| Cloudflare (DNS, TLS, WAF) | Nobody reaches any shop | Accept it; its record is better than anything you'd build. Keep DNS zone exports and the origin certificate so you can point records elsewhere. Don't lock origin access so tightly that an un-proxied emergency record can't work. |
| Safaricom M-Pesa | Prompts fail | Already handled: typed transaction codes at the till, reconciliation report. Show Safaricom status on the till so cashiers don't retry ten times. |
| KRA eTIMS | Signing fails | Already handled: queue and 5-minute retry. Add an alert when a shop's queue is older than 2 hours, and a line on the shop's Home page. |
| AWS SES / Africa's Talking | Email and SMS stop | Retries exist; add a second SMS provider only when a shop asks for guaranteed texts. |
| Paystack | Card billing fails | M-Pesa billing is the primary path in Kenya anyway. |
| The shop's internet | Till can't reach you | The offline till. Sell every shop a 4G router as part of the till kit. |

## 6. Security

The controls table in SECURITY.md is strong for this stage. The items below are what a paying
customer, an auditor or a chain's IT manager will ask about next.

### Before taking money

1. **Close the open items from the review:** session idle and absolute lifetimes with a
   "signed-in devices" list, a QZ Tray certificate per shop, Airtel callbacks limited to Airtel's
   addresses or confirmed by status query, revocable share links. They are small and the review
   already found them.
2. **Error reporting wired to `Rails.error`** so an exception in a payment callback is seen the same
   hour, not when a shop complains.
3. **The external penetration test** against staging, using the brief in SECURITY.md. Budget for a
   retest. Keep the report; chains and banks will ask for it.
4. **Secrets hygiene:** the `.kamal/secrets` file reads from the environment, which is right. Put the
   real values in a password manager with a CLI (1Password, Bitwarden) and fetch them at deploy time,
   as the file's comments suggest. Rotate the Paystack, M-Pesa, SMS and SES keys on the quarterly
   schedule in the runbook and record the date.
5. **Server access:** SSH only from a VPN or Tailscale network, keys only, with the deploy user
   separate from anyone's personal account. Console access (`bin/kamal console`) is production data
   access; log who uses it and when.
6. **Host and image hygiene:** `unattended-upgrades` on the host (in RUNBOOK §1), Dependabot on the
   Ruby base image (already configured), and a container image scan (Trivy) in CI so a vulnerable
   OpenSSL in the base image is caught before deploy.
7. **A `/.well-known/security.txt`** and a disclosure address (SECURITY.md names
   security@hardpoint.app; publish it).

### Data protection as a product feature

Kenyan hardware shops hold customers' phone numbers and KRA PINs. Under the Data Protection Act you
are the processor and the shop is the controller, and both must be registered. Beyond registration:

- **Where the data lives.** The Act allows transfers abroad with safeguards, but a shop or chain may
  prefer the data in Kenya or at least on the continent. Hosting in a provider with an African region
  removes the question and improves till latency. Whatever you choose, say it plainly on the privacy
  page.
- **Breach process.** Write the one-page plan now: who decides it is a breach, the 72-hour notice to
  the Data Commissioner, notice to affected shops through the platform announcements feature, and
  what you preserve (logs, Activity records) before fixing. The runbook's incident row for "a shop
  sees another shop's data" is the start of this.
- **Retention.** Backups keep deleted shops' data for up to 35 days; say so in the terms. The closed
  shop deletion after 30 days (`AccountDeletion`) is good; make sure the per-shop backups in the
  backups bucket are deleted with the shop.
- **Encryption at rest.** Backups are encrypted and the sensitive columns use Active Record Encryption.
  Add full-disk encryption on the database server (LUKS on the data volume, or the managed
  database's encryption), so a returned or re-provisioned VPS disk is not a leak.
- **Staff access.** Impersonation is time-boxed and visible to the shop (already done). Keep platform
  administrators to two or three people, each with two-factor (enforced already), and review the list quarterly.

### Payment security

Cards go through Paystack's hosted checkout, so HardPoint never touches card numbers; that keeps you
in the simplest PCI DSS self-assessment category (SAQ A). Keep it that way: never add a card form of
your own. M-Pesa callbacks are token-in-URL plus Safaricom address checks, idempotent by transaction
ID; the weak point is a shop's own Daraja credentials, which are encrypted at rest. Tell shops in
the help centre to use a dedicated Daraja app per shop and never to share the passkey.

### Till devices

The till is a browser on a device you don't control. In the setup package, configure Chrome in kiosk
mode with the HardPoint PWA, an OS screen lock, and no other sign-ins on the device. The SECURITY.md
guidance on lost tills (reset the staff passwords, which ends their sessions) is correct; add a
"sign out this till" button in the admin for support to use.

## 7. Reliability

### See it before the shop does

The minimum set, all of which are services you subscribe to rather than run:

| What | Tool (examples) | Alert on |
|---|---|---|
| Exceptions and slow requests | AppSignal, Honeybadger or Sentry, subscribed to `Rails.error` and the Solid Queue failures | Any new error class; payment or webhook controller errors immediately |
| Uptime | Better Stack, UptimeRobot, or Cloudflare health checks, from outside Kenya and from inside if possible | `/up` and a shop's sign-in page failing twice in a row, by SMS and phone |
| Backups | healthchecks.io heartbeat (already in `backup.sh`) and the same for WAL archiving | A missed hour |
| Jobs | `mission_control-jobs` for a queue dashboard; a check that no job is older than 15 minutes, eTIMS queue age per shop | Queue stuck, eTIMS submissions older than 2 hours |
| Database | The admin Database page (exists); `pg_stat_statements` (exists); disk, replica lag and connection count exported to the uptime tool or a small Prometheus | Disk above 80%, lag above 60 s, connections above 200 |
| Logs | Ship container logs off the server (Better Stack, Papertrail, or the APM vendor's logs) and keep 30 days | Searchable when a shop asks what happened at 14:03 |

Then a **public status page** (the uptime tool provides one) linked from the help centre, with
announced maintenance windows. A status page cuts support messages during an incident more than
any other single thing.

### Release discipline

- **CI must be green** (already: tests, tenant sweeps, Brakeman, bundler-audit, importmap audit).
  Add the k6 till scenario against staging before each monthly release, not each push.
- **Staging first, then production, then watch for an hour.** `kamal rollback` is the escape hatch;
  rehearse it once so it is known to work.
- **Migrations in two steps** (expand, then contract) for any table the till writes to, enforced by
  `strong_migrations`. Deploy during Kenyan night (02:00–04:00 EAT) when a migration touches
  `sales`, `sale_lines` or `stock_movements`; that is also the announced maintenance window.
- **Feature flags per shop** already exist (`Account::Features`). Use them for new features: switch
  on for pilot shops, watch, then default on.
- **Weekly dependency updates** (Dependabot, in the runbook) so that security upgrades are routine,
  not emergencies.

### Data integrity checks

Money software earns trust by never being wrong, not by being fast. Add a nightly job that checks
and reports, per shop, to `Rails.error` and the admin:

- Receipt numbers per branch have no gaps (`DocumentSequence`).
- Each product's stock on hand equals the sum of its ledger (`stock_movements`) at every branch.
- Every completed sale's payments sum to its total; every shift's closing count has a Z report.
- M-Pesa callbacks received with no sale attached older than a day.
- eTIMS submissions pending longer than the retry window.

These catch bugs and tampering alike, and they give the pilot's exit criterion ("a full week with no
data errors") a definition.

### Drills

The monthly restore drill in RUNBOOK §3 is the right habit. Extend it:

- Restore into staging from the newest WAL archive to a point in time, not just the dump.
- Promote the standby and run a test sale against it, then fail back.
- Pull the demo shop's internet and sell for 20 minutes on the offline till; confirm replay.
- Once a year: lose the whole provider on paper. Where are the keys, who can log in to Cloudflare, how
  long to a new server elsewhere.

Record each drill's timings in the runbook's table, as the first one is.

## 8. Availability and support

Write the SLA as one page a shop owner can read:

- **Uptime commitment:** 99.9% a month for Business and Enterprise, measured by your uptime monitor
  at the public sign-in page; excluding a published maintenance window (say, Sundays 02:00–04:00
  EAT, used only when needed), Safaricom, KRA and the shop's own connection, and the offline till's
  ability to sell is not counted as downtime.
- **Credit:** 10% of that month's fee for each full hour below the commitment, up to 50%, claimed
  within 30 days. Credits, not refunds, and only on the subscription, not on hardware or setup.
- **Support:** Starter: WhatsApp and email, 09:00–18:00 Monday to Saturday, next-business-day
  response. Business: the same hours, 2-hour response when the till can't sell, 1 business day for
  anything else. Enterprise: 07:00–20:00 seven days, 1-hour response for till-down, a named contact,
  quarterly review call.
- **What counts as "till down":** no till in the shop can record a sale online or offline. A broken
  report is not till-down.

To deliver that, you need an on-call rota (LAUNCH.md mentions it) with the uptime tool paging by
phone, a shared support inbox, the WhatsApp Business number, and the support form that already
records which page the shop was on. Two people on the rota is the minimum for a promise of 1-hour response.

## 9. What it costs to run

Rough monthly infrastructure, to be checked against current provider prices before quoting anything:

| Stage | Servers and services | Rough cost / month (USD) | Shops it carries | Break-even in Starter plans |
|---|---|---|---|---|
| 0: pilot | 1 VPS (6 core, 12 GB), object storage, Cloudflare free, SES, error tracking and uptime (free tiers) | 30–60 | up to ~50 | 2–3 |
| 1: launch | 2 web VPS, 1 jobs VPS, primary + standby DB VPS (or one managed HA Postgres), staging VPS, object storage, Cloudflare Pro, APM, uptime, log shipping | 250–500 | several hundred | 15–25 |
| 2: growth | Stage 1 plus a second-region standby, PgBouncer, Cloudflare Load Balancer | 600–1,200 | thousands | 35–60 |

The per-shop infrastructure cost falls below KES 100 a month at Stage 1 with a few hundred shops.
Hosting is not where the money goes; **people** are: setup visits, support hours and the on-call
rota. Price the setup packages so they cover the first-week cost in full, and treat the subscription
as paying for the platform and support.

Transaction costs to budget per shop: SMS (Africa's Talking per message), M-Pesa C2B charges on your
own Paybill for subscription payments, Paystack's card fee, and eTIMS is free. Put SMS on a fair-use
allowance per plan (for example 200 texts a month on Starter) with a top-up, or it becomes the one
cost that grows faster than revenue.

## 10. Order of work

Ninety days, assuming one developer plus one person selling and supporting. The pilot shops come in
at week four, when the platform can tell you it is broken; the first invoices go out at week twelve,
when there is a standby to fail over to and paper to sign.

**Weeks 1–3: see and recover**

1. Error reporting, uptime monitor with phone alerts, backup heartbeat, status page.
2. WAL archiving to a second provider's bucket; point-in-time restore drill into a scratch database.
3. Key escrow in a shared password manager; secrets fetched at deploy time.
4. Migrations moved out of the entrypoint; `strong_migrations` added.
5. Close the four open security items from the review.
6. ODPC registration started; terms, privacy notice and data processing terms drafted.

**Weeks 4–8: pilot**

7. Pilot shops on site (LAUNCH.md); WhatsApp group per shop; weekly releases through a staging server.
8. Nightly integrity checks; alerting on eTIMS queue age and stuck jobs.
9. Offline drill in a real shop; pull the internet for an hour.
10. Penetration test booked against staging; fixes released.
11. Pricing page updated with the setup packages, support tiers and backup schedule by plan.

**Weeks 9–12: launch**

12. Stage 1 infrastructure: standby database (or managed Postgres), two web servers, jobs server,
    object storage for uploads; promotion runbook rehearsed.
13. SLA published; on-call rota of two; support hours staffed.
14. Pilot shops moved to paid plans; first yearly invoices.
15. Reseller agreement with one till-hardware vendor; referral terms for accountants.
16. First monthly review of the numbers in §3 and the drill log in RUNBOOK §3.

After that, the roadmap in PLAN.md ("Features to consider next") is well chosen: the customer portal
with "Pay with M-Pesa" and automatic credit holds are the two most likely to make a shop owner pay for
Business rather than Starter.
