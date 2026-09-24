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
| Brand | "Ironworks": Steel Navy `#102A43`, Safety Orange `#F76707`, Concrete `#F5F4F1` (docs/BRAND.md) |
| Till PINs | Only for cashiers and stock clerks, and only on a till that's already signed in, so a PIN can never stand in for an owner's password + 2FA |
| Spreadsheets | CSV only (Ruby's `csv`), which Excel and Google Sheets open and save; no XLSX gem unless shops ask |
| Labels | Printed from the browser (A4 sheets or 50 × 25 mm rolls) rather than generated PDFs; barcodes via `barby` |
| Stock quantities | Kept in the product's base unit (pack sizes convert); decimals only for fractional units |
| Reorder levels | One per product. A branch "carries" a product once it has stocked it, so branches aren't nagged about lines they never sell |
| Stock takes | Differences are measured against the snapshot taken at the start, so selling during a count is fine |
| Prices and tax | Shelf prices include tax (the norm for Kenyan retail); each line's tax is its tax-inclusive share at the product's rate |
| Approvals | Owners and managers have a separate **approval PIN** that authorises one action at a cashier's till (big discount, void, return) without signing anyone in; a discount only needs approving again if it goes beyond what was already approved |
| Negative stock | Sales aren't blocked when the system shows no stock (deliveries are often booked late); the till warns and the Stock page flags branches below zero |
| Voids vs returns | A sale can be voided only while its shift is open; after that it's a return against the receipt |
| Cash drawer | Opened by the receipt printer's driver on print, or by QZ Tray's ESC/POS drawer kick on tills set up for it (Phase 8) |
| Costing | Weighted-average cost, updated on each delivery from its landed cost (goods plus a value-weighted share of transport and duty); FIFO costing stays in the backlog |
| Receiving | Goods beyond what was ordered go on a separate receipt, so each order stays a true record of what was agreed |
| Supplier payments | Settle the oldest invoices first (FIFO), which is how suppliers read their statements and what the ageing report shows |
| PDFs | Prawn 2.5 with vendored DejaVu Sans (for characters like ½ and ×); `prawn-table` is unmaintained, so tables are laid out directly. Every document shares one letterhead (`DocumentPdf`) |
| Customers | A minimal record arrives in Phase 3 (price list, credit limit, balance); statements, ageing and payments on account come in Phase 5 |
| Quotes and orders | **One document** (`CustomerOrder`) goes quote → ordered → ready → collected (or cancelled). Prices are fixed when it's written and held at collection; it's collected by loading it into a till, where the deposit is a tender |
| Invoices on account | A sale (partly) paid "on account" **is** the invoice: due after the customer's payment terms, with an A4 tax invoice PDF. No separate invoice table, so the till stays the one place money is taken |
| Receivables | Payments and returns credited to the account settle the oldest account sales first (FIFO), mirroring supplier payables; ageing and statements are based on that |
| Cash away from the sale | Cash deposits and cash account payments go through the device's till and its open shift, so the drawer count still balances |
| Credit limit | Going over it at the till needs an owner's or manager's approval PIN (or their own sign-in); the approver is recorded on the sale and in Activity |
| Stock for orders | Not reserved; orders are visible in "Open orders" and "Ready to collect". Reservation waits until shops ask |
| Deliveries | One delivery note per trip from a completed sale: pending → dispatched (driver, vehicle) → delivered (received by, optional photo of the signed note) |
| Loyalty points | Skipped (optional in the plan) |
| Cost of sales | Each sale line records its cost (weighted average at the time, ex tax; kits cost their parts) when the sale completes, so margins don't move when costs change later. Lines sold before this were back-filled at the cost of the day |
| Tax in margins | Costs are ex VAT (as a VAT-registered shop records them; input VAT is on supplier invoices) and margins are on sales ex VAT, including the product page's margin |
| Reports | Plain SQL aggregates over the shop's own rows, run on request: a year of a busy shop (60k sales, 180k lines) takes under a second, so no background jobs or summary tables yet. Queries filter by a subquery of the period's sales, because the row-level security policy's `OR` misleads the planner on plain joins |
| Report exports | CSV and PDF (landscape when wide). XLSX still waits until shops ask (CSV opens in Excel) |
| Live dashboard | Turbo 8 page refresh with morphing, broadcast (debounced) when a sale completes or is voided, a return is made, or a shift opens or closes. A custom channel only streams a shop's dashboard to its own owners, managers and accountants, on top of Turbo's signed stream names |
| Integrations without network access here | Safaricom, KRA and Africa's Talking can't be reached from the build environment, so each client is written to the published API and tested through a swappable transport (tests check the exact requests and handle the documented answers). Each has a simulator for demos and development. **Before go-live: run each against its sandbox, and have eTIMS certified by KRA** |
| M-Pesa callbacks | The shop comes from a per-shortcode secret token in the callback URL, never from the payload; production accepts only Safaricom's published IPs (Cloudflare's ranges are trusted proxies so the real IP is seen); each M-Pesa transaction ID is stored once per shop, so repeats are harmless; Safaricom always gets `ResultCode 0` |
| STK amounts | M-Pesa takes whole shillings, so a due amount with cents is rounded up in the prompt; the sale is only ever paid what's due |
| Waiting for the customer | The till polls its own server every 2.5 s while a prompt is open (not Safaricom); after 30 s without a callback the server asks Safaricom once every 10 s, and gives up after 3 minutes. Money paid after the till stopped waiting is kept as "received, not used" |
| C2B matching | Account number = an order reference → deposit on that order; = a customer's phone → payment on their account; a code already typed at a till → that payment; anything else waits at the till. Every payment to the Paybill is accepted at validation |
| eTIMS | One OSCU control unit per branch; gap-free eTIMS invoice numbers per unit fixed when a sale completes; items registered once per unit (KRA's code pattern, derived from the product); tax types from the tax rate (default 16% B, 8% E, 0% C); item class from the category or the unit's default. Voids and returns go as credit notes, only for sales that were sent |
| eTIMS failures | Unreachable → retried by a job every 5 minutes with doubling gaps (2 minutes up to 6 hours); refused → marked with KRA's reason for someone to fix and retry; selling never stops for KRA |
| SMS | Africa's Talking on the platform's account; shops opt in; at most 500 texts per shop per day; no SMS one-time passwords for sign-in (authenticator apps are safer than SMS against SIM swaps) |
| Card terminals, accounting sync | Card payments keep their typed reference until a shop's acquirer is chosen; QuickBooks/Xero sync is left out (optional in the plan; the CSV reports cover exports for now) |
| Offline selling | A service worker keeps the offline till page and its files; navigations that can't reach the server get the offline till. Nothing else is served from cache, so online pages are never stale. The catalogue snapshot (no costs) lives in IndexedDB and refreshes every 5 minutes online (ETag, so unchanged catalogues aren't sent again) |
| What works offline | Walk-in retail sales: scanning, search, packs, retail quantity breaks, cash with change, typed M-Pesa/card codes. Customers, accounts, price lists, discounts, M-Pesa prompts, returns and voids need the till online |
| Offline sales on the server | Idempotent by the till's UUID; recorded in their original shift and at the time they happened (limited to the shift's range); receipt numbers assigned on arrival (offline receipts carry a temporary number, kept on the sale). The till's price is what the customer paid, so it's kept; the server's own total wins if they differ; warnings (price since raised, stock below zero, shift already closed, total differed) go in the answer and Activity. A sale the payments don't cover is parked at its till |
| "Offline" | Measured by reaching the server (`/up`), not just the browser's online flag, so a working Wi-Fi with no internet counts as offline |
| Printing | Per till: the browser (silent with Chrome `--kiosk-printing`) or QZ Tray with ESC/POS (cut, QR, drawer kick for cash). QZ Tray 2.3.0 is vendored (LGPL-2.1, checked against npm's integrity hash) and loaded only on tills that use it. Signed requests if a certificate is set up; otherwise QZ Tray asks once |
| Customer display | A page on a second monitor fed by the till through BroadcastChannel (same browser), so it needs no server round trip and works offline |
| Weighing scales | Left out (optional in the plan): Web Serial support and scale protocols vary; kilograms are typed |
| Daily summary | Yesterday's figures at 04:15 UTC (07:15 in Nairobi), to owners, managers and accountants who haven't turned it off; nothing is sent after a day without sales |
| Plans | Starter KES 2,500 (1 branch, 2 tills, 3 staff, 2,000 products), Business KES 6,500 (3, 8, 15, 20,000), Enterprise KES 15,000 (no limits), per shop per month. Limits count what's in use (active tills and products); every feature is on every plan. Plans live in code (`Plan`), not a table, until prices need changing without a deploy. **Prices are placeholders to confirm** |
| Trial and dunning | 30 days free on the chosen plan (no card). Invoice at the trial's end, due 7 days later; reminders 3 days before the trial ends and 2 days before the due date; read-only the day after. Monthly periods run from the trial's end; a smaller plan applies only if the shop fits it; new prices from the next invoice. No proration |
| Read-only | Blocks every change (non-GET request) except paying, exporting, support, signing in/out and the user's own profile; offline sales rung up before the lock are still accepted. Suspension by the platform and closing a shop use the same lock |
| Paying HardPoint | M-Pesa prompt to the platform's own Paybill (Daraja, reusing the Phase 7 client) and cards through Paystack's hosted checkout (Kenyan cards, M-Pesa and Airtel too). Stripe left out: it doesn't settle to Kenyan businesses. Paystack confirmed twice (return page and signed webhook), idempotently. Invoices numbered from one platform sequence (`HP-2026-000123`). Bank transfers recorded by platform staff |
| Marketing site | Server-rendered pages on the bare domain in the same app (no separate CMS); help centre articles are ERB partials in the repo, searched by title and summary |
| Onboarding | A checklist worked out from the shop's data (a step done from Settings ticks itself off); only "tax rates checked" and "test receipt printed" are stored. The test receipt prints through the browser |
| Support | In-app form emailed to `SUPPORT_EMAIL` with the shop, person and page (reply-to the person), listed for platform staff; WhatsApp link to `SUPPORT_WHATSAPP`. No ticketing system until volume needs one |
| Data export | Owners only; a ZIP of one CSV per tenant table streamed with Postgres `COPY` (still under row-level security), plus staff, shop settings, images and delivery photos and a README; passwords, PIN hashes, API keys, sessions and import staging left out; emailed when ready, downloadable for 7 days |
| Closing a shop | Owner with password and the shop's address typed; read-only and owners-only at once, deleted 30 days later by a nightly job (every tenant table, files, and staff logins no other shop uses or references), cancellable until then. The platform keeps an `AccountDeletion` tombstone with the invoices it issued (tax records), nothing else |
| Platform admin | Plan change, trial extension, manual payment, suspend/restore run as the shop and are logged in its activity with the administrator's email; announcements are platform-wide banners, dismissible per browser |
| Content security policy | Enforced, not report-only: scripts from the app only, the importmap by a nonce kept in the session (stable across Turbo visits), no inline handlers (Print buttons use a Stimulus controller or a nonced script), inline styles allowed (print layouts and meters); forms to the app, shop subdomains and Paystack; QZ Tray's local websockets allowed |
| PII encryption | Secrets are encrypted per column (API keys, eTIMS keys, two-factor); customers' phone numbers and KRA PINs are not, because they're searched, matched to M-Pesa payers and printed on invoices; they rely on row-level security, filtered logs and encrypted backups |
| Rate limits | Keyed per login, per person or per till rather than per address, because a shop's tills share one public address; a looser per-address limit on sign-in remains |
| Load | Target: 95% of scans under 500 ms, payments under 800 ms. Scale by Puma workers (one per core); one Ruby process handles about 14 till requests a second |
| Database health | A small admin page reading Postgres' statistics views instead of adding PgHero (one less dependency, and it sits behind the admin sign-in); `pg_stat_statements` preloaded in production |
| Backups | Host cron with `pg_dump` in the database container, AES-256 via openssl and uploads via curl's AWS signing (no extra software); hourly database, daily files; retention by bucket lifecycle with a write-only key. RPO 1 hour, RTO 2 hours. No WAL archiving/point-in-time recovery yet: worth adding when an hour of lost sales stops being acceptable |
| Error reporting | Not chosen yet (Honeybadger, AppSignal or Sentry); a launch checklist item |
| API shape | REST and JSON under `/v1` on the `api` subdomain, the key deciding the shop (no shop subdomains in API URLs). Rendered by the same jbuilder partials as webhook payloads, so both always agree. Amounts in integer cents, quantities as decimal strings, times in UTC, bodies wrapped in the resource name (Rails' parameter wrapping off, so it's always explicit) |
| API keys | Owner-made, per app, read or read-and-write (no finer scopes until asked for); SHA-256 digests only, `hp_` prefix; costs aren't exposed and credit limits and price lists can't be set through the API |
| API and plans | Business and Enterprise only, like more branches: it's what larger shops with web shops and bookkeepers need |
| Webhooks | Delivered by background jobs with a per-minute retry sweep; HMAC-SHA256 over "timestamp.body" (Stripe's well-known scheme, so receivers can reuse code); DNS resolved once and the connection pinned to a checked public address, no redirects; deliveries kept 30 days, idempotency keys a day |
| Online store | Part of the app on the shop's own subdomain at `/store` (no separate site or theme builder), server-rendered, mobile first. On every plan: small shops want it most |
| Store checkout | No customer accounts: name and mobile number, matched to an existing customer by the last nine digits. Orders go straight to "ordered" at the shop's prices of the moment, with an unguessable link to follow them. Out-of-stock items can still be ordered ("we'll confirm"), because hardware shops order in |
| Store payments | Pay on collection, or ahead to the shop's Paybill with the order number as account number (matched by Phase 7). No prompt to the customer's phone from the store yet: that would need M-Pesa prompts tied to orders rather than sales |

| Phase | Status |
|---|---|
| 0 — Foundations | App generated; CI (with non-superuser DB role), Kamal config (Postgres 18 accessory, Cloudflare origin cert, SES SMTP) in the repo. **Server provisioning, Cloudflare, SES verification and backups still to do on real infrastructure.** |
| 1 — Tenancy & auth | **Done:** signup, subdomains, sign-in per shop, password reset, staff invitations and roles, branches, tills (registers), shop settings, TOTP 2FA with recovery codes (optionally required for owners/managers), cashier PIN quick-switch, audit `Event` log, platform super-admin with time-boxed audited impersonation, "Ironworks" branding (docs/BRAND.md), RLS with isolation tests. |
| 2 — Catalogue & inventory | **Done:** categories, brands, units, tax rates, price lists and quantity breaks, products with barcodes, pack sizes, kits and photos, trigram search, stock ledger with reconciliation, adjustments, transfers, stock takes with approval, reorder list, daily low-stock email, CSV import (20k rows in ~12 s) and export, barcode labels. |
| 3 — POS checkout | **Done:** till selection per device, shifts with float/drops/payouts/X and blind-count Z reports, scanner-first cart with packs, decimals, serials and price lists, line and sale discounts with manager approval PIN, split tender (cash, M-Pesa code, card, on account), gap-free receipt numbers per branch, stock deducted on completion, park/recall, voids and returns with approval, 80 mm receipts and email receipts, sales history, minimal customers. 10-line split-payment sale ≈ 2.6 s. |
| 4 — Purchasing & suppliers | **Done:** suppliers and supplier products (cost, lead time, minimum order, preferred), purchase orders with PDF by email, partial/full receiving with landed costs and weighted-average costing, reorder suggestions with one-click orders, supplier invoices, FIFO payments and ageing. |
| 5 — Customers, credit, quotes & invoices | **Done:** customer addresses and payment terms; quotes and orders with PDF/email, validity dates, deposits (and refunds) and collection at the till; account sales as invoices with A4 tax invoice PDFs; payments on account (FIFO), statements (PDF/email), ageing and a "Who owes us" report; delivery notes with dispatch and proof of delivery; credit-limit override by approval PIN; deposits and account payments on the X/Z report. Loyalty skipped. |
| 6 — Reporting & dashboards | **Done:** live owner dashboard (Solid Cable), eight reports (sales and margin by day/month/branch/cashier/category/product, profit and loss, VAT, payments by method, discounts/voids/returns, stock valuation, dead stock, shifts) plus the existing movement history and ageing reports, period and branch filters, CSV and PDF export, cost recorded on each sale line, daily summary email with opt-out. Measured at a year of 180k sale lines: under 1 s per report. |
| 7 — Payment & tax integrations | **Done (to be proven against the live sandboxes):** M-Pesa Daraja per shop (encrypted credentials, STK push from the till with automatic completion, C2B confirmations with automatic matching to orders, accounts and typed codes, reconciliation report, token-and-IP-checked idempotent callbacks), KRA eTIMS OSCU per branch (initialisation, item registration, sales and credit notes, signed receipts with QR code, retry queue, refusals to fix), SMS via Africa's Talking (receipts, order ready, balance reminders), simulators for all three. Card terminals stay manual; accounting sync skipped. |
| 8 — Offline mode & hardware | **Done:** installable till, service worker with the offline till, IndexedDB catalogue snapshot and sale queue, automatic idempotent sync with warnings, connection indicator, QZ Tray ESC/POS printing with drawer kick and no-sale logging, customer display. Tested end to end in a browser by stopping the server mid-shift. Weighing scales skipped. |
| 9 — SaaS business layer | **Done (payments to be proven against Safaricom's and Paystack's sandboxes):** public site (home, pricing, privacy, help centre with 11 guides), signup with plan choice and a 30-day trial, setup checklist with test receipt, three plans with enforced limits, monthly invoices with PDF and reminders, payment by M-Pesa prompt or Paystack card checkout, read-only mode for unpaid shops, in-app help with WhatsApp and support requests, full data export (ZIP of CSVs) and 30-day account closure with a tombstone, platform admin with revenue and usage, plan changes, trial extensions, manual payments, suspend/restore, announcements and the support inbox. |
| 12 — Online store | **Done:** Settings › Online store; public catalogue with categories, search, stock per collection branch and a session cart; checkout without accounts; online orders marked in Orders with staff emails, customer text and email, and an order-tracking page with Paybill instructions; closed while the shop is locked; spam limits. |
| 11 — Public API & webhooks | **Done:** API keys in Settings › Developers, REST API v1 (shop, branches, products, stock levels, customers, sales, orders with click-and-collect ordering and cancelling) with cursor paging, sync filters, idempotency keys, rate limits and read-only enforcement; webhooks for nine events with signing, retries, auto-disable with an email, redelivery and test events, public-address-only delivery; developer docs; cross-shop sweep over the API. |
| 10 — Hardening, performance & launch | **Done in code (the rest needs real infrastructure and shops):** cross-tenant sweep of all 136 member routes, enforced CSP, HSTS, permissions policy, log filtering, shop-friendly rate limits, Dependabot and weekly scans; k6 load test (40 cashiers, p95 scan 278 ms) with the cart's N+1 fixed; every foreign key indexed; tuned PostgreSQL config and connection budget; admin Database page; encrypted backups with a restore script, drilled locally; runbook, security brief and launch plan. **Still to do:** provision the VPS, the external penetration test, the drill on the real server, sandbox certification (M-Pesa, eTIMS), and the pilot (docs/LAUNCH.md). |

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

### Phase 11 — Public API & webhooks
**Goal:** shops (and their developers, storefronts and accounting tools) can read and change their data
over a documented REST API and be told about changes by webhooks.
- **API keys** per shop, made by the owner in Settings › Developers: a name, read or read-and-write,
  shown once and stored only as a digest, revocable, with last use recorded. On the Business and
  Enterprise plans.
- **REST API** at `https://api.hardpoint.app/v1` (JSON, bearer token): the shop and branches; products
  (list, show, create, update) with prices, barcodes and stock; stock levels; customers (list, show,
  create, update); sales (list, show, read-only); orders (list, show, create for click-and-collect,
  cancel). Cursor pagination, `updated_since` filters, idempotency keys on creates, rate limits per key,
  consistent errors. Blocked from writing while the shop is read-only.
- **Webhooks:** endpoints per shop choosing events (sale completed/voided, product created/updated,
  stock changed, order created/updated, customer created/updated), signed with HMAC-SHA256,
  retried with back-off for a day, switched off after repeated failures with an email to the owner,
  recent deliveries with redelivery, a test event. Only HTTPS to public addresses.
- **Developer docs** on the public site.

### Phase 12 — Online store with click-and-collect
**Goal:** every shop can put its catalogue online at `yourshop.hardpoint.app/store` and take orders for
collection, without a separate website.
- **Settings › Online store:** switch it on, a headline and introduction, collection branches, a note on
  collection times, a contact number, and whether to show stock levels. Products can be left out of the store.
- **Public store** (mobile first): categories, search, product pages with image, price and whether it's in stock
  at each collection branch; a cart; checkout with name, phone and collection branch (no account needed).
- **Orders** arrive as confirmed orders marked "Online" in Orders, with an email to owners and managers; the
  customer gets a confirmation page (and a text, where SMS is on) with a link to follow the order, and a text
  when it's ready. Paying ahead by M-Pesa uses the shop's Paybill with the order number as the account, which
  Phase 7's matching already turns into a deposit; otherwise they pay when collecting.
- Closed while the shop is read-only, suspended or closing; protected against spam (rate limits, a honeypot,
  sane quantities). On all plans.

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
