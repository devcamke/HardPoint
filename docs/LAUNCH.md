# Launch plan

From a working staging server to paying shops. Tick each line when done.

## Before the pilot

- [ ] Production and staging VPSs set up and hardened (docs/RUNBOOK.md §1)
- [ ] Cloudflare DNS, Full (strict) TLS, WAF, rate-limiting rule on `/session`
- [ ] SES out of the sandbox; DKIM, SPF and DMARC pass (send a test of every mailer)
- [ ] Backups running, heartbeat alerting, bucket lifecycle and write-only key (RUNBOOK §2)
- [ ] First restore drill on the real server, timed; RTO confirmed (RUNBOOK §3)
- [ ] Uptime check on `https://hardpoint.app/up` and one shop's sign-in page, alerting by SMS
- [ ] Error reporting chosen and wired to `Rails.error` (e.g. Honeybadger, AppSignal or Sentry)
- [ ] M-Pesa: every flow run against Safaricom's sandbox (prompt, callback, C2B confirmation and
      validation, register URLs); then go-live approval for the platform Paybill
- [ ] KRA eTIMS: sandbox tests passed and the integration certified by KRA
- [ ] Paystack: live keys, webhook URL, a real card payment refunded
- [ ] Africa's Talking: sender ID approved; texts delivered to Safaricom and Airtel numbers
- [ ] External penetration test done and findings fixed (docs/SECURITY.md)
- [ ] Load test repeated against staging on the production VPS size (perf/README.md)
- [ ] Prices confirmed; privacy page and terms reviewed by a lawyer; company details in
      `credentials.billing.company` for invoices; registered as a data controller/processor with the ODPC
- [ ] Support inbox and WhatsApp number staffed during shop hours (`SUPPORT_EMAIL`, `SUPPORT_WHATSAPP`)

## Pilot: 2–3 real hardware stores, about 4 weeks

Pick shops that differ: one small single counter, one with a yard or second branch, one with trade
customers on account. Free during the pilot (extend their trial from the admin).

- Week 0: set each one up with them on site: import their products, tills and printers, staff and PINs,
  M-Pesa and eTIMS. Watch the first hour of selling.
- Weeks 1–4: a WhatsApp group per shop; visit weekly; watch the admin (errors, Database page, support
  requests); release fixes weekly.
- Measure: time to ring up a typical sale, receipts that didn't print, sales sent offline, stock
  differences at a count, M-Pesa payments not matched, support questions by topic.
- Exit when: a full week with no data errors, cashiers faster than their old system, owners use the
  daily summary and reports, and nothing in the support queue older than a day.

## General launch

- [ ] Fixes from the pilot released; help centre updated with the pilot's questions
- [ ] Pilot shops move to paid plans (or a launch discount)
- [ ] Marketing site live; signups open
- [ ] On-call rota and the runbook's incident table known to whoever is on call
