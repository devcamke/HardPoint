# HardPoint — Multi-Tenant Hardware Store POS

A phased build plan for a SaaS point-of-sale and inventory system for hardware stores.
Each shop (tenant) is fully isolated: no shop can see another shop's products, sales,
customers, staff, or reports.

## Decisions & progress

| Decision | Choice |
|---|---|
| Ruby / Rails | **Ruby 4.0.7**, **Rails 8.1.3** (latest stable) |
| Database | **PostgreSQL 18** (latest stable; 19 is still in beta) |
| CSS | **Tailwind CSS 4** via `tailwindcss-rails` 4.x |
| Tenant isolation | **Keep Postgres row-level security** alongside `Current.account` scoping (§2) |
| Style | Vanilla Rails: built-ins first, rich models, CRUD controllers, Minitest + fixtures (§1) |

| Phase | Status |
|---|---|
| 0 — Foundations | App generated; CI (with non-superuser DB role), Kamal config (Postgres 18 accessory, Cloudflare origin cert, SES SMTP) in the repo. **Server provisioning, Cloudflare, SES verification and backups still to do on real infrastructure.** |
| 1 — Tenancy & auth | **Done:** signup, subdomains, sign-in per shop, password reset, staff invitations and roles, branches, shop settings, RLS with isolation tests. **Remaining:** TOTP 2FA, cashier PIN quick-switch, registers, platform super-admin, audit `Event` model. |
| 2–10 | Not started |

---

## 1. Philosophy & technology stack

### Guiding principle: vanilla Rails
Build it the way Rails itself (and 37signals' apps such as Basecamp, HEY, Fizzy) is built:

- **Rails defaults first.** If Rails ships it (auth generator, Solid Queue/Cache/Cable,
  Hotwire, Importmap, Propshaft, Kamal, Minitest, fixtures, `rate_limit`, Active Record
  Encryption, Active Storage, Action Mailer), use it. No replacement gems.
- **A gem only where Rails has no answer** (e.g. generating PDFs or XLSX files), and
  each one has to justify itself. The list is short and explicit below.
- **Rich domain models, thin controllers.** Business logic lives in Active Record models
  and **concerns** (`Sale::Payable`, `Product::Stockable`, `Account::Subscribable`), not in
  service objects, interactors, form objects, or a `app/services` folder.
- **Everything is CRUD.** When an action isn't CRUD, make it a new resource:
  voiding a sale is `resource :void` → `Sales::VoidsController#create`; closing a shift is
  `Shifts::ClosuresController#create`; receiving a PO is `PurchaseOrders::ReceiptsController#create`.
- **`Current` attributes** (`Current.account`, `Current.user`, `Current.session`,
  `Current.branch`) for request context.
- **Jobs stay thin**: `sale.transmit_to_tax_authority_later` enqueues a job whose `perform`
  just calls `sale.transmit_to_tax_authority_now`. The logic stays on the model.
- **Server-rendered HTML + Hotwire.** Turbo Frames/Streams and small Stimulus controllers;
  no SPA and no JSON API for our own UI.
- **Callbacks, `delegated_type`, `store_accessor`, `enum`, `normalizes`,
  `generates_token_for`, `has_secure_password`, `encrypts`**: reach for these built-ins first.
- **Minitest + fixtures + system tests.** No RSpec, FactoryBot or mocking frameworks.
- **One database, one app, one server** until measurement says otherwise.

### Stack
| Layer | Choice (Rails default unless noted) | Notes |
|---|---|---|
| Framework | **Ruby on Rails 8.1** on Ruby 4.0 | |
| Database | **PostgreSQL 18** | Your pick; RLS provides a DB-level safety net |
| CSS | **Tailwind CSS v4** via `tailwindcss-rails` | Your pick; the official `--css=tailwind` option, no Node |
| Frontend | **Hotwire**: Turbo + Stimulus | POS screen, live updates |
| JS / assets | **Importmap** + **Propshaft** | No bundler, no Node |
| Web server | **Puma** + **Thruster** | HTTP caching/compression, X-Sendfile |
| Jobs | **Solid Queue** (+ Mission Control – Jobs UI, a Rails gem) | Recurring jobs via `config/recurring.yml` |
| Cache | **Solid Cache** | |
| WebSockets | **Solid Cable** | Live dashboards / stock updates |
| Authentication | **`bin/rails generate authentication`** + `has_secure_password` | Sessions table, password resets built in |
| Authorization | Plain Ruby: `Membership` `enum :role` + model predicates (`user.can_void?`) + `before_action` | No policy gem |
| Multi-tenancy | **Associations off `Current.account`** + Postgres RLS | No tenancy gem (see §2) |
| Money | `integer` cents columns + a tiny `Money`-formatting concern / `number_to_currency` | No money gem |
| Search | Postgres `pg_trgm` / full-text via plain scopes | No search gem |
| Pagination | Simple `limit`/`offset` (or keyset) scope in a concern; or `geared_pagination` (37signals) | |
| Audit trail | Own `Event` model (polymorphic `eventable`, `action`, `particulars` jsonb, `creator`) recorded from model callbacks | Same approach Basecamp uses |
| Rate limiting | Rails 8 **`rate_limit`** in controllers | Plus Cloudflare rate-limit rules |
| Secrets / PII | Rails **credentials** + **Active Record Encryption** (`encrypts`) | Payment API keys, tax PINs |
| Files | **Active Storage** → S3-compatible service (Contabo Object Storage / Cloudflare R2) | |
| Email | **Action Mailer over SMTP** to the **AWS SES SMTP endpoint** | No AWS SDK gem needed |
| Charts | Server-rendered SVG/CSS bars in views, or a Chart.js import-map pin + a Stimulus controller | |
| Receipts | HTML view + 80mm print CSS, `window.print()` | Works with any thermal printer driver |
| Testing | **Minitest**, **fixtures**, **system tests** (Capybara + Selenium, Rails default) | Two-tenant fixtures for isolation tests |
| Lint / security | **rubocop-rails-omakase**, **Brakeman**, `bin/importmap audit` | All generated by `rails new` |
| CI | GitHub Actions workflow generated by `rails new` | |
| Deploy | **Kamal 2** + kamal-proxy | Generated by `rails new` |
| Offline POS | Rails 8 **PWA** scaffold (`app/views/pwa/manifest`, `service-worker`) + IndexedDB queue | |

### The deliberate, short gem list (only where Rails has no built-in)
| Need | Gem | Why it's unavoidable |
|---|---|---|
| PDF invoices, quotes, statements | `prawn` (+ `prawn-table`) | Rails can't generate PDFs |
| Barcode images for shelf labels | `barby` (or render Code128 as SVG in a helper) | No built-in |
| XLSX import/export | `caxlsx` / `roo` (or stick to **CSV**, which Ruby's stdlib handles) | Start with CSV; add only if shops demand Excel |
| TOTP two-factor auth | `rotp` (+ `rqrcode` for the QR) | No built-in; alternative is emailed one-time codes with `generates_token_for` |
| Error tracking | `sentry-ruby`/`sentry-rails`, or Rails 8's `Rails.error` reporter + a subscriber that emails you | Optional |

Everything else (payments, tax e-invoicing, SMS) is plain `Net::HTTP` calls wrapped in a
model or concern (`MobileMoney::Payment`, `Etims::Transmission`). No vendor SDK gems.

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
| Schema per tenant | Strong | Medium-high, slow migrations, needs a gem | Avoid |
| **Shared tables + `account_id`, scoped through associations, + Postgres RLS** | Strong (DB-enforced) | Low | **Chosen** |

The tenant is called an **`Account`** (the Rails/37signals convention). A shop's business
is one account.

### How isolation is enforced: three layers, no tenancy gem
1. **Routing layer**: each shop gets a subdomain, `acme.hardpoint.app`. A controller
   concern resolves the account from the subdomain and sets `Current.account`:
   ```ruby
   # app/controllers/concerns/account_scoped.rb
   module AccountScoped
     extend ActiveSupport::Concern
     included { before_action :set_current_account }

     private
       def set_current_account
         Current.account = Account.find_by!(subdomain: request.subdomain)
       end
   end
   ```
   A user can only sign in to an account they have a `Membership` in.
2. **Application layer**: **never query a tenant model from its class**. Always go through
   the account's associations, the way Basecamp does:
   ```ruby
   @product = Current.account.products.find(params[:id])     # ✅
   @product = Product.find(params[:id])                       # ❌ never
   ```
   Every tenant model `belongs_to :account, default: -> { Current.account }`.
   Child records (sale lines, payments) inherit the account from their parent.
   Jobs serialize the account that was current when they were enqueued and restore it
   before loading their arguments (`config/initializers/active_job_account.rb`).
   No `default_scope`: explicit association scoping is the Rails way and is easy to review.
3. **Database layer (decided: kept)**: Postgres Row-Level Security on every tenant table,
   added in the migration with `enable_row_level_security :products`, which creates:
   ```sql
   ALTER TABLE products ENABLE ROW LEVEL SECURITY;
   ALTER TABLE products FORCE ROW LEVEL SECURITY;   -- applies to the table owner too
   CREATE POLICY account_isolation ON products
     USING (current_setting('app.bypass_rls', true) = 'on'
            OR account_id = NULLIF(current_setting('app.current_account_id', true), '')::bigint)
     WITH CHECK (<same>);
   ```
   - `Current.account=` sets `app.current_account_id` on the request's connection, and
     `Current` resetting clears it. Pool checkout also clears it, so a connection never
     carries one shop's setting into another request.
   - **Fail closed:** with no account set, no tenant rows are visible or writable.
   - `Account.without_isolation { }` sets `app.bypass_rls` for work that legitimately spans
     shops: fixtures, seeds, platform admin, and signing a user out of every shop.
   - `config.active_record.schema_format = :sql` (`db/structure.sql`) so policies are dumped.
   - Rails connects as the **non-superuser `hardpoint` role without `BYPASSRLS`** in every
     environment, including development, test and CI. That role owns the tables, and
     `FORCE ROW LEVEL SECURITY` makes the policies apply to it.
   - Because a regular role can't disable FK triggers, foreign keys are
     `DEFERRABLE INITIALLY IMMEDIATE` (`add_foreign_key ..., deferrable: :immediate`), and the
     test helper defers them while loading fixtures.
   - `test/models/account/isolation_test.rb` fails if a table with `account_id` lacks the policy,
     if a foreign key isn't deferrable, or if the database role could bypass RLS.

### Other isolation rules
- Every unique index includes `account_id` (e.g. `UNIQUE (account_id, sku)`), so two shops
  can both have SKU `CEM-50KG`. Model validations use `uniqueness: { scope: :account_id }`.
- Composite foreign keys (or validations) ensure a sale line can't point to another
  account's product.
- Active Storage keys prefixed with `accounts/<id>/`; files served via Rails' signed,
  expiring blob URLs after an account check.
- Cache keys include the account (`cache [Current.account, @product]`).
- Per-account document numbers (`INV-000123` per shop, gap-free, generated under a row
  lock on the account/branch counter).
- **Automated leak tests**: fixtures for two accounts; tests assert every controller,
  report, export and job returns zero rows of the other account.
- Super-admin impersonation is recorded as an `Event` and time-boxed.

### Tenant hierarchy
```
Platform (you)
 └── Account (a business, e.g. "Acme Hardware Ltd")  ← isolation boundary
      ├── Branches / Locations (Main St shop, Warehouse, Branch 2)
      │    └── Registers / Tills
      └── Users (via memberships with a role, optionally limited to branches)
```
Branches are inside an account, so one business with several branches sees consolidated
reports, while different businesses never see each other.

---

## 3. Core domain model (initial sketch)

```
accounts(id, name, subdomain, currency, timezone, tax_pin, plan, status, settings jsonb)
users(id, email, password_digest, name, otp_secret, ...)          -- global identity
memberships(account_id, user_id, role, branch_ids[], pin_hash)     -- cashier quick PIN
branches(account_id, name, address, phone)
registers(account_id, branch_id, name, receipt_printer_config)

categories(account_id, parent_id, name)
brands(account_id, name)
units(account_id, name, abbreviation)                  -- pc, box, kg, m, ft, bag, litre
products(account_id, sku, barcode, name, category_id, brand_id, base_unit_id,
         cost_cents, price_cents, tax_rate_id, track_stock, serialised, reorder_level,
         allow_decimal_qty, active)
product_units(account_id, product_id, unit_id, factor, barcode, price_cents)
                                                      -- box of 100 screws = 100 pc
product_variants(...)                                 -- sizes/colours if needed
price_lists(account_id, name)                          -- retail, contractor, wholesale
price_list_items(account_id, price_list_id, product_id, price_cents, min_qty)
tax_rates(account_id, name, rate, inclusive)

stock_levels(account_id, branch_id, product_id, quantity)          -- cached balance
stock_movements(account_id, branch_id, product_id, qty_change, kind,
                source_type, source_id, unit_cost_cents, user_id) -- immutable ledger
serial_numbers(account_id, product_id, serial, status, sale_line_id)
stock_transfers(+ lines) · stock_counts(+ lines) · stock_adjustments(+ reason codes)

suppliers(account_id, ...) · purchase_orders(+ lines) · goods_receipts(+ lines)
supplier_invoices · supplier_payments

customers(account_id, name, phone, email, tax_pin, price_list_id, credit_limit_cents)
customer_ledger_entries(account_id, customer_id, amount_cents, kind, source)
quotations(+ lines) → sales_orders → invoices / sales

shifts(account_id, register_id, user_id, opening_float, closing_count, variance)
sales(account_id, branch_id, register_id, shift_id, customer_id, number, status,
      subtotal, discount, tax, total, offline_uuid)
sale_lines(account_id, sale_id, product_id, unit_id, qty, unit_price, discount, tax)
payments(account_id, sale_id, method, amount_cents, reference, status)
                                     -- cash, card, mobile money, credit, split tender
refunds / returns(+ lines, restock flag)
cash_movements(account_id, shift_id, kind, amount, reason)   -- payouts, drops
delivery_notes(+ lines)
events(account_id, eventable_type, eventable_id, action, particulars jsonb, creator_id)
                                     -- audit trail, recorded from model callbacks
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
- Keep what `rails new` generates: rubocop-rails-omakase, Brakeman, `bin/importmap audit`,
  the GitHub Actions CI workflow, Kamal config, PWA files, Dockerfile.
- `config.active_record.schema_format = :sql` (needed for RLS policies).
- A `docs/CONVENTIONS.md` stating the vanilla-Rails rules from §1 so every contributor follows them.
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
  - Create **SES SMTP credentials** (an IAM user limited to `ses:SendRawEmail`) and configure
    Action Mailer's built-in `:smtp` delivery (`email-smtp.<region>.amazonaws.com`, port 587,
    STARTTLS), credentials in Rails credentials. Deliver with `deliver_later` (Solid Queue).
- **Backups**: nightly `pg_dump` (or pgBackRest with WAL archiving) to off-site object
  storage (not the same VPS), encrypted, 30-day retention. Test a restore.
- **Monitoring**: `Rails.error` reporting (optionally to Sentry), Uptime Kuma, PgHero
  (a Rails engine), log rotation. Mission Control – Jobs mounted for admins.
- Staging environment (a second small VPS or a separate Kamal destination).

**Exit criteria:** `git push main` → tests → deploy; HTTPS works on a test subdomain;
a test email lands in an inbox with DKIM/SPF/DMARC passing; a restore has been tested.

### Phase 1 — Multi-tenant core, auth & roles (Weeks 3–5)
**Goal:** Shops can sign up, get a subdomain, invite staff, and are fully isolated.

- `accounts`, `users`, `sessions`, `memberships`, `branches`, `registers`
  (start from `bin/rails generate authentication`).
- Subdomain resolution middleware/concern, reserved subdomains (`www`, `admin`, `api`, `app`, `mail`).
- `AccountScoped` controller concern; all lookups via `Current.account.<association>`;
  `Current.account`, `Current.user`, `Current.branch`.
- **Postgres RLS** migrations + helper to set `app.current_account_id` per request and per job.
- Authentication: email/password, password reset & email confirmation (via SES),
  TOTP 2FA for owners/managers, session management, device list.
- **Cashier quick-switch**: 4–6 digit PIN on a logged-in register for fast shift changes.
- Roles as `enum :role` on `Membership` (owner, manager, cashier, stock_clerk, accountant);
  permission predicates on the model (`membership.can_void_sales?`) enforced with
  `before_action :ensure_can_void_sales`; branch-restricted access.
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
- Fast product search: `pg_trgm` GIN index + a `Product.search(query)` scope in plain SQL
  on name/SKU/barcode.

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
- Silent printing & cash drawer control via a local print agent (e.g. QZ Tray) or kiosk-mode
  browser printing,
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
- Security headers/CSP (`config/initializers/content_security_policy.rb`), `encrypts` for secrets and PII, log scrubbing
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
             │  PostgreSQL 18 (RLS, app role w/o BYPASSRLS) │
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
- RLS on every tenant table; CI test fails if a new table has `account_id` without a policy.
- App DB role cannot bypass RLS; migrations use a separate role.
- 2FA for owners/admins; lockout + rate limits on login and PIN entry.
- Every controller inherits `AccountScoped` + `Authentication`; a test asserts that no
  controller calls a tenant model class directly (`Product.find`), and code review checks it.
- Encrypted secrets (Rails credentials / Kamal secrets); per-account payment credentials
  encrypted at rest with `encrypts`.
- Audit log for prices, discounts, voids, refunds, stock adjustments, permission changes.
- Cloudflare-only origin access; SSH hardened; automatic security updates.
- Backups encrypted, off-site, restore-tested quarterly.
- Brakeman + `bin/importmap audit` in CI (as generated by `rails new`); Dependabot.

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
