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
| Authorisation | Roles (owner, manager, cashier, stock clerk) checked in controllers; approvals by PIN for discounts, voids, returns and credit | `app/controllers/concerns/authorization.rb` |
| Platform staff | Separate admin subdomain and sign-in with two-factor; impersonation is time-boxed and recorded in the shop's activity; every plan change, suspension, trial extension and manual payment is recorded with the administrator's email | `app/controllers/admin` |
| Web | Content security policy enforced (scripts only from the app, nonce for the importmap, no inline handlers, no plugins, no framing, forms only to the app, shop subdomains and Paystack); HSTS including subdomains; Permissions-Policy; CSRF protection; Rails' default headers | `config/initializers/content_security_policy.rb`, `permissions_policy.rb` |
| Webhooks | M-Pesa: per-shortcode secret token in the URL and Safaricom's addresses only; idempotent by transaction ID. Paystack: HMAC-SHA512 signature over the raw body; idempotent. Card checkout only redirects to `https://*.paystack.com` | `app/controllers/webhooks` |
| Secrets | M-Pesa API keys, eTIMS keys and two-factor secrets encrypted with Active Record Encryption; everything else in Rails credentials; `config/master.key` never committed | |
| Logs | Passwords, PINs, two-factor and recovery codes, phone numbers, KRA PINs, M-Pesa payers' names and numbers, tokens and signatures are filtered from logs | `config/initializers/filter_parameter_logging.rb` |
| Personal data | Owners can export all their shop's data and close the shop (deleted after 30 days); support access is visible to the shop. Customer phone numbers and KRA PINs are not encrypted column by column: phone numbers are searched and matched to M-Pesa payers, and KRA PINs print on every tax invoice. They're protected by row-level security, filtered logs and encrypted backups | `docs/RUNBOOK.md` |
| Backups | Hourly, AES-256 encrypted before leaving the server, write-only bucket key | `config/backup` |
| Dependencies | Dependabot weekly (gems, GitHub Actions, the Docker base image); Brakeman, bundler-audit and importmap audit on every push and weekly | `.github` |

## Checked in CI on every push

- Row-level security is on and forced for every tenant table; the app's role can't bypass it.
- The cross-tenant route sweep (136 routes).
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
2. Moving up in a shop: a cashier doing a manager's work (discounts, voids, returns, credit, staff,
   settings, billing, exports, closing the shop); bypassing approval PINs; brute-forcing PINs.
3. Authentication: session handling across subdomains, password reset, two-factor bypass, admin
   impersonation tokens, rate limits.
4. Money: forging or replaying M-Pesa and Paystack callbacks, paying less than a sale or invoice,
   racing two payments, tampering with offline sales (prices, totals, times).
5. Web: XSS in anything a shop can type (product names, customer names, receipt footers, support
   messages) including in PDFs and emails; CSP bypass; CSRF.
6. The read-only and closing locks: changing anything while a shop is read-only, suspended or closing.

**Reporting:** findings with steps to reproduce and severity; retest after fixes. Findings and fixes are
kept in this file's history.
