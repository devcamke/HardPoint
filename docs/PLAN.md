# HardPoint — Multi-Tenant Hardware Store POS

A phased build plan for a SaaS point-of-sale and inventory system for hardware stores.
Each shop (tenant) is fully isolated: no shop can see another shop's products, sales,
customers, staff, or reports.

---

## 1. Technology stack

### Your picks
| Layer | Choice | Notes |
|---|---|---|
| Framework | **Ruby on Rails 8.x** (Ruby 3.4) | Full-stack, "one-person framework" |
| Database | **PostgreSQL 17** | Row-Level Security (RLS) is the backbone of tenant isolation |
| Styling | **Tailwind CSS v4** via `tailwindcss-rails` | No Node build step needed |

### Additions recommended
| Concern | Choice | Why |
|---|---|---|
| Frontend interactivity | **Hotwire (Turbo + Stimulus)** | Fast, SPA-like POS screen without React |
| JS delivery | **Importmap** + **Propshaft** | Rails 8 defaults, no bundler |
| Background jobs | **Solid Queue** | DB-backed, no Redis needed |
| Cache | **Solid Cache** | DB/disk-backed cache |
| WebSockets | **Solid Cable** | Live dashboard / stock updates |
| Multi-tenancy | **`acts_as_tenant`** + **Postgres RLS** | App-level scoping *and* DB-enforced isolation |
| Authentication | Rails 8 auth generator (or **Devise**) + **TOTP 2FA** (`rotp`) | 2FA for owners/admins |
| Authorization | **Pundit** | Roles: owner, manager, cashier, stock clerk, accountant |
| Money | **`money-rails`** | Integer cents, no float rounding bugs |
| Search | **`pg_search`** + `pg_trgm` | Fast fuzzy product lookup at the till |
| Pagination | **Pagy** | Fastest Rails paginator |
| Audit trail | **`paper_trail`** or `audited` | Who changed prices / voided sales |
| PDFs | **Prawn** + `prawn-table` | Receipts, invoices, quotations, delivery notes |
| Barcodes | **`barby`** (generate), keyboard-wedge USB scanners (read) | Shelf labels, product lookup |
| Receipt printing | Browser print (80mm CSS) → later **QZ Tray** / ESC/POS | Thermal printers, cash drawer kick |
| Spreadsheets | **`caxlsx`** (export), **`roo`** (import) | Bulk product import, report export |
| Charts | **Chartkick** + **Groupdate** | Dashboards |
| Email | **AWS SES** via `aws-sdk-rails` (`:ses_v2` delivery) | Transactional mail |
| File storage | **Active Storage** → S3-compatible (Contabo Object Storage / Cloudflare R2 / S3) | Product images, logos, imports |
| Deployment | **Kamal 2** + **kamal-proxy** + **Thruster** | Docker deploys to the Contabo VPS, zero-downtime |
| Rate limiting | Rails 8 `rate_limit` + **`rack-attack`** | Login brute-force protection |
| Error tracking | **Sentry** (or Honeybadger / AppSignal) | Exceptions & performance |
| Uptime | **Uptime Kuma** (self-hosted) or Better Stack | Alerting |
| DB insight | **PgHero** | Slow queries, index advice |
| Backups | **pgBackRest** or `pg_dump` cron → offsite object storage | Point-in-time recovery |
| Security scanning | **Brakeman**, **bundler-audit**, **importmap audit** | In CI |
| Code style | **rubocop-rails-omakase** | Rails 8 default |
| Testing | **Minitest** (or RSpec) + **Capybara** system tests + **FactoryBot** | Includes cross-tenant leak tests |
| CI/CD | **GitHub Actions** | Test → scan → `kamal deploy` |
| Offline POS | **PWA**: service worker + IndexedDB sale queue | Till keeps selling when internet drops |
| SaaS billing | Stripe / Paystack / M-Pesa (region dependent) | Charging shops a subscription |

### Payments & tax (region dependent)
If operating in Kenya: **M-Pesa Daraja API** (STK Push, C2B Till/Paybill callbacks) and
**KRA eTIMS** integration for tax invoices (VAT 16%). Elsewhere, swap in the local
equivalents (card terminal integration, local fiscal/e-invoicing API).

---

## 2. Multi-tenancy architecture (the most important decision)

### Options considered
| Strategy | Isolation | Ops cost | Verdict |
|---|---|---|---|
| Database per tenant | Strongest | High (migrations × N, connections) | Overkill for small shops |
| Schema per tenant (Apartment) | Strong | Medium-high; gem poorly maintained, slow migrations | Avoid |
| **Shared tables + `tenant_id` + Postgres RLS** | Strong (DB-enforced) | Low | **Chosen** |

### How isolation is enforced — three layers
1. **Routing layer** — each shop gets a subdomain: `acme.hardpoint.app`.
   A `Current.tenant` is resolved from the subdomain on every request; users can only log
   into a tenant they belong to (`memberships` table).
2. **Application layer** — `acts_as_tenant :tenant` on every tenant-owned model. All
   queries are automatically scoped with `WHERE tenant_id = ?`; creating a record without
   a current tenant raises an error. Background jobs carry `tenant_id` and set it before
   running.
3. **Database layer (defense in depth)** — Postgres Row-Level Security on every tenant table:
   ```sql
   ALTER TABLE products ENABLE ROW LEVEL SECURITY;
   ALTER TABLE products FORCE ROW LEVEL SECURITY;
   CREATE POLICY tenant_isolation ON products
     USING (tenant_id = current_setting('app.current_tenant_id')::bigint)
     WITH CHECK (tenant_id = current_setting('app.current_tenant_id')::bigint);
   ```
   The app sets `SET LOCAL app.current_tenant_id = ...` inside each request/job transaction
   (around_action / job callback). The Rails app connects as a **non-superuser role without
   `BYPASSRLS`**, so even a forgotten scope or raw SQL cannot read another shop's rows.
   A separate privileged role is used only for migrations and the platform super-admin.

### Other isolation rules
- Every unique index includes `tenant_id` (e.g. `UNIQUE (tenant_id, sku)`), so two shops
  can both have SKU `CEM-50KG`.
- Composite foreign keys (or model validations) ensure a sale line can't point to another
  tenant's product.
- Active Storage keys prefixed with `tenants/<id>/`; files served only via signed,
  expiring URLs after a tenant check.
- Cache keys namespaced by tenant.
- Per-tenant sequences for receipt/invoice numbers (`INV-000123` per shop, gap-free,
  generated under a row lock).
- **Automated leak tests**: a test suite that creates two tenants and asserts every
  controller/endpoint, report and export returns zero rows of the other tenant.
- Super-admin impersonation is audited and time-boxed.

### Tenant hierarchy
```
Platform (you)
 └── Tenant (a business, e.g. "Acme Hardware Ltd")  ← isolation boundary
      ├── Branches / Locations (Main St shop, Warehouse, Branch 2)
      │    └── Registers / Tills
      └── Users (via memberships with a role, optionally limited to branches)
```
Branches are inside a tenant, so one business with several branches sees consolidated
reports, while different businesses never see each other.

---

## 3. Core domain model (initial sketch)

```
tenants(id, name, subdomain, currency, timezone, tax_pin, plan, status, settings jsonb)
users(id, email, password_digest, name, otp_secret, ...)          -- global identity
memberships(tenant_id, user_id, role, branch_ids[], pin_hash)     -- cashier quick PIN
branches(tenant_id, name, address, phone)
registers(tenant_id, branch_id, name, receipt_printer_config)

categories(tenant_id, parent_id, name)
brands(tenant_id, name)
units(tenant_id, name, abbreviation)                  -- pc, box, kg, m, ft, bag, litre
products(tenant_id, sku, barcode, name, category_id, brand_id, base_unit_id,
         cost_cents, price_cents, tax_rate_id, track_stock, serialised, reorder_level,
         allow_decimal_qty, active)
product_units(tenant_id, product_id, unit_id, factor, barcode, price_cents)
                                                      -- box of 100 screws = 100 pc
product_variants(...)                                 -- sizes/colours if needed
price_lists(tenant_id, name)                          -- retail, contractor, wholesale
price_list_items(tenant_id, price_list_id, product_id, price_cents, min_qty)
tax_rates(tenant_id, name, rate, inclusive)

stock_levels(tenant_id, branch_id, product_id, quantity)          -- cached balance
stock_movements(tenant_id, branch_id, product_id, qty_change, kind,
                source_type, source_id, unit_cost_cents, user_id) -- immutable ledger
serial_numbers(tenant_id, product_id, serial, status, sale_line_id)
stock_transfers(+ lines) · stock_counts(+ lines) · stock_adjustments(+ reason codes)

suppliers(tenant_id, ...) · purchase_orders(+ lines) · goods_receipts(+ lines)
supplier_invoices · supplier_payments

customers(tenant_id, name, phone, email, tax_pin, price_list_id, credit_limit_cents)
customer_ledger_entries(tenant_id, customer_id, amount_cents, kind, source)
quotations(+ lines) → sales_orders → invoices / sales

shifts(tenant_id, register_id, user_id, opening_float, closing_count, variance)
sales(tenant_id, branch_id, register_id, shift_id, customer_id, number, status,
      subtotal, discount, tax, total, offline_uuid)
sale_lines(tenant_id, sale_id, product_id, unit_id, qty, unit_price, discount, tax)
payments(tenant_id, sale_id, method, amount_cents, reference, status)
                                     -- cash, card, mobile money, credit, split tender
refunds / returns(+ lines, restock flag)
cash_movements(tenant_id, shift_id, kind, amount, reason)   -- payouts, drops
delivery_notes(+ lines)
audit logs (paper_trail versions, tenant-scoped)
```
Stock is an **append-only movement ledger**; `stock_levels` is a cache updated in the
same transaction (with `SELECT ... FOR UPDATE`) so balances are always explainable.

---

## 4. Hardware-store–specific requirements to design for

- **Multiple units of measure** — buy cement by the tonne, sell by the bag; nails by the kg
  or by the box; timber and pipe by the metre/foot; wire by the roll or metre.
- **Decimal quantities** (2.5 m of chain, 0.75 kg of nails).
- **Contractor / trade accounts** — credit sales, credit limits, statements, aging.
- **Tiered pricing** — retail vs contractor vs wholesale, quantity breaks.
- **Quotations** — contractors ask for quotes, which convert to invoices/sales later.
- **Delivery notes** and deliveries/dispatch for bulky items.
- **Serial numbers & warranties** for power tools and generators.
- **Cut/mixed items** — paint tinting, cut-to-length items, kits/bundles (e.g. "plumbing
  kit" consuming several SKUs).
- **Large catalogues** (10k–50k SKUs) → fast search, bulk import, barcode label printing.
- **Special orders** — customer orders an item not in stock, deposit taken.
- **Tool hire/rental** (later phase, optional).

---

## 5. Phased delivery plan

Timelines assume 1–2 developers; adjust to your team. Each phase ends with something
deployable and usable.

### Phase 0 — Foundations & infrastructure (Weeks 1–2)
**Goal:** An empty Rails app running in production on the Contabo VPS behind Cloudflare,
sending email through SES, with CI/CD.

- `rails new hardpoint --database=postgresql --css=tailwind` (Rails 8, Solid Queue/Cache/Cable).
- Repo conventions: rubocop-rails-omakase, Brakeman, bundler-audit, GitHub Actions CI.
- **Contabo VPS hardening**
  - Ubuntu 24.04 LTS, non-root deploy user, SSH keys only, disable password & root login.
  - `ufw`: allow 22 (ideally from your IP only), 80/443 **only from Cloudflare IP ranges**.
  - `fail2ban`, unattended-upgrades, swap file, time sync.
  - Docker installed (Kamal needs it).
- **PostgreSQL**: run as a Kamal accessory (Docker, volume on disk) *or* natively on the host
  (easier tuning/backups). Create two roles: `hardpoint_owner` (migrations) and
  `hardpoint_app` (no superuser, no BYPASSRLS).
- **Kamal 2** config: web + job roles, kamal-proxy, Thruster, health checks,
  secrets via `.kamal/secrets` (never committed).
- **Cloudflare**
  - DNS: `hardpoint.app` and wildcard `*.hardpoint.app` → VPS IP, **proxied** (orange cloud).
  - SSL mode **Full (strict)** with a **Cloudflare Origin CA certificate** (covers the apex and
    `*.hardpoint.app`) installed in kamal-proxy (custom cert support), or Let's Encrypt
    via DNS-01 if you prefer.
  - WAF managed rules, rate-limiting rule on `/session`, "Always use HTTPS", HSTS,
    bot fight mode, caching rules for `/assets/*`.
  - Confirm kamal-proxy host routing accepts the wildcard/any host so every tenant
    subdomain reaches the app.
- **AWS SES**
  - Verify the domain; add **DKIM** CNAMEs, **SPF** (`include:amazonses.com`) with a
    custom MAIL FROM subdomain (`mail.hardpoint.app`), and a **DMARC** record — all in Cloudflare
    DNS (DNS-only, grey cloud).
  - Request production access (leave sandbox).
  - Configuration set + SNS topic → webhook endpoint in the app for **bounces and
    complaints**; suppress those addresses.
  - IAM user limited to `ses:SendEmail`/`ses:SendRawEmail`.
- **Backups**: nightly `pg_dump` (or pgBackRest with WAL archiving) to off-site object
  storage (not the same VPS), encrypted, 30-day retention. Test a restore.
- **Monitoring**: Sentry, Uptime Kuma, PgHero, log rotation.
- Staging environment (a second small VPS or a separate Kamal destination).

**Exit criteria:** `git push main` → tests → deploy; HTTPS works on a test subdomain;
a test email lands in an inbox with DKIM/SPF/DMARC passing; a restore has been tested.

### Phase 1 — Multi-tenant core, auth & roles (Weeks 3–5)
**Goal:** Shops can sign up, get a subdomain, invite staff, and are fully isolated.

- `tenants`, `users`, `memberships`, `branches`, `registers`.
- Subdomain resolution middleware/concern, reserved subdomains (`www`, `admin`, `api`, `app`, `mail`).
- `acts_as_tenant` on all tenant models; `Current.tenant`, `Current.user`, `Current.branch`.
- **Postgres RLS** migrations + helper to set `app.current_tenant_id` per request and per job.
- Authentication: email/password, password reset & email confirmation (via SES),
  TOTP 2FA for owners/managers, session management, device list.
- **Cashier quick-switch**: 4–6 digit PIN on a logged-in register for fast shift changes.
- Pundit roles: Owner, Manager, Cashier, Stock Clerk, Accountant; branch-restricted access.
- Staff invitations by email.
- Tenant settings: business name, logo, currency, timezone, tax PIN, receipt footer.
- Platform **super-admin** at `admin.hardpoint.app` (separate auth, audited impersonation).
- Cross-tenant leak test suite (runs in CI forever after).
- Base Tailwind layout & component set (buttons, forms, tables, modals, flash, dark mode).

**Exit criteria:** Two demo shops cannot access each other's data via UI, URL tampering,
or direct SQL as the app role.

### Phase 2 — Catalogue & inventory (Weeks 6–9)
**Goal:** A shop can load its full product list and track stock per branch.

- Categories, brands, units of measure, tax rates.
- Products with SKU, barcode(s), cost, price, reorder level, images, serialised flag,
  decimal quantity flag.
- **Unit conversions** (`product_units`): sell by piece/box/kg/metre with per-unit barcode/price.
- Kits/bundles.
- Price lists (retail / contractor / wholesale) and quantity-break pricing.
- **CSV/XLSX bulk import** with preview, validation errors, and background processing;
  export too.
- Stock ledger (`stock_movements`) + cached `stock_levels`.
- Opening stock, adjustments with reason codes (damage, theft, expiry, correction).
- **Stock transfers** between branches (send → in transit → receive).
- **Stock takes** (full or cycle counts), variance report, approval step.
- Low-stock alerts (dashboard + daily email digest).
- Barcode **label printing** (PDF sheets and 2-inch label printers).
- Fast product search (`pg_search` + trigram on name/SKU/barcode).

**Exit criteria:** Import 20k products in minutes; stock value report reconciles to ledger.

### Phase 3 — POS checkout (Weeks 10–14)
**Goal:** Cashiers can ring up sales quickly and reliably.

- Full-screen POS UI (Turbo + Stimulus), keyboard-first; touch-friendly for tablets.
- Barcode scanner input (keyboard-wedge), search-as-you-type, quick-pick favourites.
- Cart: qty (incl. decimals), unit selection, line/cart discounts (with permission
  thresholds and manager override PIN), price-list auto-selection by customer.
- **Shifts**: open with float, cash drops, payouts, close with blind count, X/Z reports,
  over/short variance.
- Payments: cash (change calc), card (manual reference first), mobile money,
  **split tender**, on-account (credit) for approved customers.
- Park/hold and recall sales; void lines/sales (audited, permission-gated).
- **Returns & refunds** against original receipt, restock or write-off.
- Receipts: 80mm thermal CSS print template, reprint, email receipt (SES), optional SMS.
- Cash drawer kick via printer.
- Sale numbering per tenant/branch, gap-free.
- Serial number capture at sale for serialised items.
- Stock deducted in the same transaction as the sale.

**Exit criteria:** A cashier completes a 10-line scanned sale with split payment in
under 30 seconds; shift closes with correct variance.

### Phase 4 — Purchasing & suppliers (Weeks 15–17)
- Suppliers, supplier price/lead time per product.
- **Purchase orders** (draft → sent by email as PDF → partially/fully received).
- **Goods Received Notes** updating stock and cost (weighted-average cost; FIFO later if needed).
- Reorder suggestions from reorder levels + sales velocity → one-click PO.
- Supplier invoices, payments, supplier balance / aging.
- Landed costs (transport, duty) apportioned to lines (optional).

### Phase 5 — Customers, credit, quotes & invoices (Weeks 18–21)
- Customer profiles, trade/contractor accounts, assigned price list, credit limit, terms.
- **Quotations** (PDF/email) → convert to sale or invoice; validity dates.
- Sales orders & **special orders** with deposits.
- **Invoices on account**, customer payments & allocation, customer statements (PDF/email),
  aging buckets (30/60/90).
- **Delivery notes**, dispatch status, proof of delivery.
- Credit limit enforcement at the till (manager override).
- Loyalty points (optional).

### Phase 6 — Reporting & dashboards (Weeks 22–24)
- Owner dashboard: today's sales, margin, top products, cash position, low stock (live
  via Solid Cable).
- Reports: sales by day/branch/cashier/category/product, gross margin, tax (VAT) report,
  payments by method, discounts & voids, stock valuation, dead stock, stock movement
  history, shift reports, customer & supplier aging, profit & loss (simple).
- Filters, date ranges, CSV/XLSX/PDF export; scheduled email reports (e.g. daily summary).
- Heavy reports run as background jobs; add read-optimised summary tables/materialised
  views where needed (still tenant-scoped).

### Phase 7 — Payment & tax integrations (Weeks 25–28)
*(Adapt to your market.)*
- **Mobile money** — e.g. M-Pesa Daraja: STK Push from the till, C2B confirmation callbacks,
  automatic payment matching, reconciliation report. Credentials stored per tenant
  (encrypted with Active Record Encryption), since each shop has its own Till/Paybill.
- **Card terminals** — integrate the local acquirer's API or keep manual reference entry.
- **Tax authority e-invoicing** — e.g. KRA eTIMS (OSCU/VSCU): device registration per branch,
  transmitting sales/credit notes, printing the control unit info and QR code on receipts,
  retry queue for failures.
- **SMS** (receipts, statements, OTPs) — Africa's Talking, Twilio, or local provider.
- Accounting export/sync — QuickBooks Online / Xero (optional).
- All webhooks: signature/IP verification, idempotency keys, tenant resolution from
  the credential, not from the payload.

### Phase 8 — Offline mode & hardware polish (Weeks 29–32)
- **PWA**: installable POS, service worker caching the POS shell, product catalogue
  snapshot in IndexedDB.
- **Offline sales queue**: sales recorded locally with a client UUID and synced when online
  (idempotent via `offline_uuid`); conflict handling for stock going negative.
- Connection indicator; cash-only mode when offline (mobile-money/eTIMS queued).
- Silent printing & cash drawer control via **QZ Tray** (or a small local print agent),
  ESC/POS commands, customer-facing display (optional), weighing scale input (optional).

### Phase 9 — SaaS business layer (Weeks 33–35)
- Public marketing site & pricing page.
- Self-service **signup → subdomain → onboarding wizard** (branches, taxes, import products,
  invite staff, print test receipt).
- **Subscription plans** & limits (branches, registers, users, SKUs) enforced per tenant;
  trial period; billing via Stripe/Paystack/M-Pesa; dunning emails; read-only mode on
  non-payment.
- Super-admin: tenant list, usage metrics, plan changes, suspend/restore, impersonation,
  announcements.
- **Tenant data export** (full CSV/ZIP) and account deletion process (data protection laws,
  e.g. Kenya DPA / GDPR).
- Help centre / in-app guides; support ticket or WhatsApp link.

### Phase 10 — Hardening, performance & launch (Weeks 36–38)
- External **penetration test** focused on tenant isolation, IDOR, auth.
- Load test the POS endpoints (k6) with realistic concurrency.
- Postgres tuning (`pgtune` for VPS size), index review via PgHero, connection limits.
- Disaster-recovery drill: rebuild production from backups onto a fresh VPS, document RTO/RPO.
- Security headers/CSP, Active Record Encryption for secrets and PII, log scrubbing
  (`filter_parameters`), dependency update routine (Dependabot).
- Pilot with 2–3 real hardware stores → fix → general launch.

### Beyond v1 (backlog)
- Native/mobile companion app (stock counts via phone camera scanning — Hotwire Native).
- E-commerce storefront / click-and-collect per tenant.
- Public REST API with per-tenant API keys and webhooks.
- Tool hire/rental module; job/project costing for contractors.
- Multi-currency; FIFO costing; batch/lot tracking.
- Scaling out: move Postgres to its own VPS (or managed DB), add read replica, split
  job workers onto a second VPS — Kamal handles multi-host.

---

## 6. Infrastructure topology

```
                 Users (browsers / PWA tills)
                            │ HTTPS
                  ┌─────────▼──────────┐
                  │     Cloudflare      │  DNS, *.hardpoint.app wildcard, WAF,
                  │  (proxy, TLS, CDN)  │  rate limits, DDoS protection
                  └─────────┬──────────┘
                            │ Full (strict) TLS, Origin CA cert
             ┌──────────────▼─────────────────────────────┐
             │ Contabo VPS (Ubuntu 24.04, ufw: CF IPs only) │
             │  kamal-proxy ─► Rails web (Puma + Thruster)  │
             │                 Rails jobs (Solid Queue)     │
             │  PostgreSQL 17 (RLS, app role w/o BYPASSRLS) │
             └───────┬──────────────────────┬──────────────┘
                     │                      │
        ┌────────────▼─────────┐   ┌────────▼──────────────────┐
        │ AWS SES (email) +    │   │ Object storage (off-site): │
        │ SNS bounce webhooks  │   │ uploads + encrypted backups│
        └──────────────────────┘   └───────────────────────────┘
```

**Starting VPS size:** Contabo "Cloud VPS" with ~6–8 vCPU / 12–16 GB RAM / NVMe is plenty
for dozens of shops. Keep staging on a smaller instance.

---

## 7. Security checklist (applies to every phase)
- RLS on every tenant table; CI test fails if a new table has `tenant_id` without a policy.
- App DB role cannot bypass RLS; migrations use a separate role.
- 2FA for owners/admins; lockout + rate limits on login and PIN entry.
- Pundit `verify_authorized` / `verify_policy_scoped` in all controllers.
- Encrypted secrets (Rails credentials / Kamal secrets); per-tenant payment credentials
  encrypted at rest.
- Audit log for prices, discounts, voids, refunds, stock adjustments, permission changes.
- Cloudflare-only origin access; SSH hardened; automatic security updates.
- Backups encrypted, off-site, restore-tested quarterly.
- Brakeman + bundler-audit in CI; Dependabot.

---

## 8. Testing strategy
- Model/unit tests for pricing, tax, unit conversion, stock ledger math.
- System tests (Capybara + headless Chrome) for the full POS flow, returns, shifts.
- **Tenant isolation tests** for every model, controller, report, export, job, and webhook.
- Concurrency tests for stock deduction and document numbering.
- Offline sync tests (duplicate submission, out-of-order sync).

---

## 9. Suggested milestones summary
| Phase | Weeks | Deliverable |
|---|---|---|
| 0 Foundations | 1–2 | Prod pipeline, Cloudflare, SES, backups |
| 1 Tenancy & auth | 3–5 | Isolated shops, staff roles |
| 2 Inventory | 6–9 | Catalogue, stock ledger, imports |
| 3 POS | 10–14 | **MVP: sell at the till** |
| 4 Purchasing | 15–17 | POs, GRNs, suppliers |
| 5 Customers & credit | 18–21 | Quotes, invoices, statements |
| 6 Reporting | 22–24 | Dashboards & reports |
| 7 Integrations | 25–28 | Mobile money, tax e-invoicing, SMS |
| 8 Offline & hardware | 29–32 | PWA offline till, silent printing |
| 9 SaaS layer | 33–35 | Signup, billing, super-admin |
| 10 Launch | 36–38 | Pen test, DR drill, pilot shops |

A usable pilot (Phases 0–3) is achievable in roughly **3–4 months**; the full v1 in
**~9 months** for a small team.
