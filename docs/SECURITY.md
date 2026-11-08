# HardPoint security

What protects shops' data, what is tested automatically, and the brief for the external penetration
test. Report vulnerabilities to security@hardpoint.app.

## What matters most

1. **One shop must never see or change another shop's data.** Many shops share one database.
2. **Money and tax records must be right and unforgeable:** sales, payments, M-Pesa callbacks, eTIMS.
3. **Accounts:** owners' and platform administrators' logins, till PINs, approvals.
4. **Personal data** under the Kenya Data Protection Act: customers' names, phones, KRA PINs; staff.

## Controls

| Area | Control | Where |
|---|---|---|
| Tenant isolation | Every query goes through `Current.account`; Postgres **row-level security** on all 56 tables with an `account_id`, enforced even for the table owner; the app connects as a role without superuser or `BYPASSRLS` | `config/initializers/row_level_security.rb`, `test/models/account/isolation_test.rb` |
| | Automated sweep: signed in as one shop's owner, every one of the 136 routes that takes a record id is requested with another shop's record; all must be refused or not found | `test/integration/tenant_isolation_sweep_test.rb` |
| | Session cookies are per subdomain (not shared across shops); sessions are looked up within the shop | `app/controllers/concerns/authentication.rb` |
| Authentication | `has_secure_password` (bcrypt); TOTP two-factor with recovery codes, required for platform admins and optionally for a shop's owners and managers; password reset ends every session | |
| | Rate limits: sign-in 10 per 3 minutes per login and 60 per address (a shop's tills share one address); two-factor codes per person; PIN switching per till with PIN lockout after repeated failures; sign-up, password reset | controllers' `rate_limit` |
| Authorisation | Roles (owner, manager, cashier, stock clerk, accountant) checked in controllers; only owners give, change or remove the owner role; approvals by PIN for discounts, voids, returns and credit, with at most 10 wrong approval PINs per shop in 15 minutes | `app/controllers/concerns/authorization.rb`, `app/controllers/memberships_controller.rb`, `app/models/approval.rb` |
| Sessions | Removing a member of staff deletes their sessions; a session without a membership is refused. Passwords need 10 characters on every path (sign-up, invitation, reset, profile) | `app/models/membership.rb`, `app/controllers/concerns/authentication.rb`, `app/models/user.rb` |
| Offline sync | A sale goes only into a shift of the till sending it, by staff who can sell; hand discounts from the offline till are ignored with a warning; negative prices refused | `app/models/sale/offline.rb` |
| Exports | CSV cells that a spreadsheet would run as a formula are written as text (leading apostrophe) in reports, product and QuickBooks exports | `app/models/safe_csv.rb` |
| Uploads | Only through the app's forms (Active Storage direct uploads closed); product photos are images up to 5 MB; delivery proof photos images only | `config/routes.rb`, `app/models/product.rb` |
| Platform staff | Separate admin subdomain and sign-in with two-factor; impersonation is time-boxed and recorded in the shop's activity; every plan change, suspension, trial extension and manual payment is recorded with the administrator's email | `app/controllers/admin` |
| Web | Content security policy enforced (scripts only from the app, nonce for the importmap, no inline handlers, no plugins, no framing, forms only to the app, shop subdomains and Paystack); HSTS including subdomains; Permissions-Policy; CSRF protection; Rails' default headers | `config/initializers/content_security_policy.rb`, `permissions_policy.rb` |
| Public API | Keys stored as SHA-256 digests, shown once, revocable; the key decides the shop and requests run under row-level security; read-only keys can't write; 600 requests a minute per key; no writes while a shop is locked; changes recorded in Activity under the key's name; an API sweep test aims another shop's key at every record route | `app/controllers/api/v1` |
| Outgoing webhooks | HTTPS only; the host is resolved once and every address checked against private, loopback, link-local and carrier-grade NAT ranges before connecting to that same address (no DNS rebinding), no redirects; signed with HMAC-SHA256 and a per-endpoint secret stored encrypted | `app/models/webhook_delivery/transport.rb` |
| Webhooks | M-Pesa: per-shortcode secret token in the URL and Safaricom's addresses only; idempotent by transaction ID. Paystack: HMAC-SHA512 signature over the raw body; idempotent. Card checkout only redirects to `https://*.paystack.com` | `app/controllers/webhooks` |
| Secrets | M-Pesa API keys, eTIMS keys and two-factor secrets encrypted with Active Record Encryption; everything else in Rails credentials; `config/master.key` never committed | |
| Logs | Passwords, PINs, two-factor and recovery codes, phone numbers, KRA PINs, M-Pesa payers' names and numbers, tokens and signatures are filtered from logs | `config/initializers/filter_parameter_logging.rb` |
| Personal data | Owners can export all their shop's data and close the shop (deleted after 30 days); support access is visible to the shop. Customer phone numbers and KRA PINs are not encrypted column by column: phone numbers are searched and matched to M-Pesa payers, and KRA PINs print on every tax invoice. They're protected by row-level security, filtered logs and encrypted backups | `docs/RUNBOOK.md` |
| Till devices | The offline till keeps a snapshot on the device (IndexedDB): the catalogue, and customers' names, phone numbers, price lists and points balances so sales can be in their name offline. Only signed-in staff at an open shift get it; it's replaced as things change. Tills are the shop's own devices: when one is lost, reset the passwords of the staff who used it (which ends their sessions); when one is given away, sign out and clear the browser's site data first | `app/models/pos_catalogue.rb` |
| Backups | Continuous WAL archiving shipped off-site every minute plus hourly dumps and weekly base backups, all AES-256 encrypted before leaving the server, write-only bucket key; restore to any minute | `config/backup`, `config/postgres/postgresql.conf` |
| Sessions | End after 14 days unused or 90 days in all; every device listed on My profile with sign-out; nightly purge | `app/models/session.rb`, `app/controllers/my/devices_controller.rb` |
| Shared links | A row per link, random 32-character token, 30 days, revocable from the document's page, opens counted; statements fixed to their period | `app/models/document_share.rb` |
| Alerting | Unhandled errors, exhausted job retries and failing platform checks reach the operators within minutes (Sentry or email), and `/health` tells the uptime monitor; see docs/RUNBOOK.md §7 | `config/initializers/error_reporting.rb`, `app/models/platform_health.rb` |
| Staging | A scrambled copy of production (`staging:anonymise`): no real names, numbers, credentials or outbound connections; every email redirected | `lib/tasks/staging.rake`, `config/initializers/staging.rb` |
| Email | Through AWS SES, DKIM-signed with a custom MAIL FROM; bounces and complaints come back through an SNS topic whose messages are verified against Amazon's signing certificate (and the known topic ARN) before anything in them is believed; addresses that bounce or complain are never written to again | `app/models/sns/message.rb`, `app/controllers/webhooks/ses_controller.rb`, `app/models/email_suppression.rb` |
| Disclosure | `/.well-known/security.txt` names the security address; the data processing terms promise breach notice within 72 hours | `app/controllers/pages_controller.rb`, `/data-processing` |
| Dependencies | Dependabot weekly (gems, GitHub Actions, the Docker base image); Brakeman, bundler-audit and importmap audit on every push and weekly | `.github` |

## Checked in CI on every push

- Row-level security is on and forced for every tenant table; the app's role can't bypass it.
- The cross-tenant route sweeps (146 app routes, and every API route with another shop's key).
- Every foreign key is indexed (deleting a shop, exports).
- Security headers and the content security policy; no inline event handlers.
- Webhook signature and token checks; rate limits on sign-in.
- Brakeman: 0 warnings (2 reviewed and recorded in `config/brakeman.ignore`).

## Penetration test brief

**Scope:** `https://*.hardpoint.app` (a staging deployment with production settings), the admin
subdomain, the webhooks, and the till's offline sync API. Out of scope: Cloudflare, Contabo,
Safaricom, KRA and Paystack themselves; denial of service.

**Accounts provided:** two shops (A and B), each with an owner, a manager with two-factor, a cashier
with a till PIN and a stock clerk; a platform admin account with two-factor; test M-Pesa and Paystack
credentials (sandbox).

**Please focus on:**
1. Reaching shop A's data from shop B: IDs in URLs and forms, Turbo Stream and JSON endpoints, file
   downloads (receipts, PDFs, exports, product images), Action Cable streams (the live dashboard),
   the offline sales API, search endpoints, and anything that takes a subdomain or host header.
2. The public API and webhooks: another shop's records with a valid key, writing with a read-only key, key
   enumeration, rate limits, and aiming a webhook at internal addresses (metadata services, the database,
   DNS rebinding).
3. Moving up in a shop: a cashier doing a manager's work (discounts, voids, returns, credit, staff,
   settings, billing, exports, closing the shop); bypassing approval PINs; brute-forcing PINs.
4. Authentication: session handling across subdomains, password reset, two-factor bypass, admin
   impersonation tokens, rate limits.
5. Money: forging or replaying M-Pesa and Paystack callbacks, paying less than a sale or invoice,
   racing two payments, tampering with offline sales (prices, totals, times).
6. Web: XSS in anything a shop can type (product names, customer names, receipt footers, support
   messages) including in PDFs and emails; CSP bypass; CSRF.
7. The read-only and closing locks: changing anything while a shop is read-only, suspended or closing.

**Reporting:** findings with steps to reproduce and severity; retest after fixes. Findings and fixes are
kept in this file's history.

## Internal review, November 2026

Found by reading the code before the external test, and fixed (Phase 32 in docs/PLAN.md):

| Severity | Finding | Fix |
|---|---|---|
| High | A manager could make themselves owner, add owners, or demote and remove an owner | Owner role only given, changed or removed by owners; the role picker hides it |
| High | Approval PINs (4–6 digits) could be guessed with no limit, then used to approve discounts, voids, returns and credit | 10 wrong approval PINs per shop in 15 minutes, then none accepted until the window passes |
| High | Offline sync took the cashier, shift and hand discounts from the request | Shift must be the sending till's; the cashier must be able to sell; hand discounts ignored with a warning; negative prices refused |
| Medium | Store checkout wrote a visitor's email onto the existing customer with that phone number and showed their name | The record is never changed from the store; what was typed goes on the order's note; no name on the order page |
| Medium | CSV exports could carry spreadsheet formulas typed by customers or staff | Formula-like cells escaped; import strips the escape |
| Medium | Product images had no type or size check; direct uploads were open to anyone | Image types and 5 MB limit; direct-upload route closed |
| Medium-low | Removed staff kept working sessions | Sessions deleted on removal; sessions without a membership refused |
| Low-medium | Reset and invitation links accepted a one-character password | 10-character minimum on the user |
| Low | No rate limit on M-Pesa/Airtel prompts or on setting PINs (which checks the password) | Rate limits per till session |
| Medium | QZ Tray signing used one platform key, so one shop's till could obtain signatures another shop's QZ Tray would trust | Each shop signs with its own key and certificate (`Account::QzSigning`), issued under the platform's QZ certificate when there is one; a signature from one shop means nothing to another's tills |
| Low | Sessions didn't expire | Sessions end after 14 days unused and 90 days in all; My profile lists every signed-in device with sign-out per device and "everywhere else"; expired sessions are purged nightly |
| Low | Airtel callbacks weren't limited to Airtel's addresses | Every "paid" callback is confirmed with Airtel's status API before a sale is paid, and `AIRTEL_CALLBACK_IPS` restricts the source addresses when Airtel publishes them |
| Low | Share links couldn't be revoked, and a statement link showed the period of the day it was opened | Each link is a `DocumentShare` row the shop can take back from the document's page (recorded in Activity); statements are fixed to the period they were sent with; opens are counted |
