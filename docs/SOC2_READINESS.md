# SOC 2 readiness

Where HardPoint stands against SOC 2, written from the code and the runbook in November 2026. It is a working
map for whoever takes HardPoint through an audit, not a claim of compliance and not an auditor's opinion.

## What SOC 2 is, and why this isn't it yet

SOC 2 is a report by an independent audit firm (a licensed CPA firm) on a company's controls, measured against
the AICPA's Trust Services Criteria. Nobody "implements" it in code: the software supplies some of the controls,
and the company supplies the rest (written policies, people, records that the controls were really followed).

- **Type I** says the controls are suitably designed on one date. A few weeks of auditor time once the gaps
  below are closed.
- **Type II** says they operated over a period, usually 3 to 12 months, and is what buyers normally ask for.
  The period can't start until the controls and their record-keeping are in place.

Only the **Security** criteria are mandatory. Availability and Confidentiality are the two worth adding for a
service shops run their tills on; Processing Integrity and Privacy are optional and can wait.

**Until a report exists, don't write "SOC 2 compliant" anywhere** (site, sales emails, contracts). What can be
said truthfully today is what the controls are: docs/SECURITY.md lists them.

## Summary

| Area | Standing |
|---|---|
| Technical controls in the product (access, isolation, encryption, logging, backups) | Strong: most of what an auditor looks for is built and tested |
| Operations (monitoring, incidents, recovery, change control) | Written down in docs/RUNBOOK.md; little evidence yet that it's followed, because there's no production history |
| Company controls (policies, risk assessment, people, vendors) | Mostly missing: this is the bulk of the work |
| Independent testing | Internal assessment done (docs/SECURITY.md, November 2026); the external penetration test isn't booked |

## Security (the Common Criteria)

| Criteria | What the auditor wants to see | What HardPoint has | Gap |
|---|---|---|---|
| **CC1** Control environment | Who is responsible for security; a code of conduct; background checks; an organisation chart | Nothing written | Name a security owner. Write a short code of conduct and have everyone sign it. Decide on background checks for anyone with production access |
| **CC2** Communication | Staff know the policies; customers know the commitments and how to report a problem | `/privacy`, `/terms`, `/data-processing`, `/sla`; `/.well-known/security.txt` and security@hardpoint.app; breach notice within 72 hours promised in the data processing terms | Internal policies to communicate (below). The legal pages are still awaiting a lawyer's review (docs/LAUNCH.md) |
| **CC3** Risk assessment | A written risk register, reviewed at least yearly, including fraud risk | The threat list in docs/SECURITY.md ("What matters most") and its findings history | Turn it into a register: each risk with likelihood, impact, owner and treatment; review it yearly and after any incident |
| **CC4** Monitoring of controls | Evidence the controls are checked: internal reviews, penetration tests, findings tracked to closure | CI on every push (row-level security forced on every tenant table and its policy present, cross-shop route sweeps, security headers, webhook signatures, rate limits); Brakeman, bundler-audit and importmap audit on every push and weekly; internal review and assessment with findings and fixes in docs/SECURITY.md | Book the external penetration test and retest. Close the open row-level-security hardening finding (docs/SECURITY.md) on staging |
| **CC5** Control activities | Policies that say what the controls are, approved and versioned | The controls exist; the policies describing them don't | The policy set below |
| **CC6.1** Logical access | Authentication, authorisation, encryption of secrets | bcrypt passwords with a 10-character minimum; TOTP two-factor with recovery codes, required for platform administrators and available to (or required of) a shop's owners and managers; optional Sign in with Google for existing staff; five roles checked in controllers; approval PINs with lockout; API keys kept as SHA-256 digests with read-only scope; integration secrets under Active Record Encryption | None in the product. SAML single sign-on isn't offered (large customers may ask) |
| **CC6.2 / 6.3** Giving and removing access | New access is approved; leavers lose access promptly; access is reviewed periodically | In a shop: invitations that expire, owner-only control of the owner role, removing a member ends their sessions at once. Platform: administrators are made only from the console, enrol two-factor with a one-time link; quarterly review of `User.where(admin: true)` is in the runbook | Keep a record each time the quarterly review is done. A written joiner/leaver checklist covering every system (server SSH, Cloudflare, GitHub, AWS, the password manager), not only the app |
| **CC6.6** Boundary protection | Protection from outside threats | Cloudflare in front with Full (strict) TLS; HSTS including subdomains; strict content security policy; Permissions-Policy; CSRF protection; rate limits on every sign-in path; M-Pesa callbacks only from Safaricom's addresses; outgoing webhooks blocked from private addresses | Cloudflare WAF and the `/session` rate-limiting rule are on the launch list, not yet set up |
| **CC6.7** Data in transit and on devices | Encryption in transit; control of data leaving the system | TLS everywhere (`force_ssl`); backups AES-256 encrypted before leaving the server; exports only by owners and never during a support session; CSV formula escaping | Disk encryption on staff laptops, and a rule about where exports and database copies may be kept |
| **CC6.8** Malicious software | Prevention and detection of unauthorised software | Uploads limited to images through the app's forms; dependency scanning; Dependabot weekly for gems, Actions and the base image | Endpoint protection on staff machines; a server patching routine (unattended security upgrades on the VPS) written into the runbook |
| **CC7.1 / 7.2** Detecting problems | Vulnerability management; monitoring for anomalies | Sentry or email for every unhandled error; `PlatformHealthJob` every 10 minutes; `/health` for an outside monitor; two backup heartbeats; shop Activity and the platform Audit page record sign-ins, support access, and every plan or billing change | The uptime monitor and alert routing aren't set up yet (launch list). Decide how long logs are kept and write it down |
| **CC7.3 – 7.5** Incidents | A response plan, followed and recorded; lessons learned | The incident table in RUNBOOK §5, including "a shop reports seeing another shop's data" as a security incident | A fuller plan: severities, who decides, who tells customers and the ODPC and when; an incident log; a post-incident review template; one tabletop exercise a year |
| **CC8** Change management | Changes are reviewed, tested and approved before production; emergency changes are recorded | Every change goes through a pull request with CI (tests, linters, scanners); `strong_migrations` blocks unsafe migrations; migrations run once per deploy; staging before production (RUNBOOK §8, §9); rollback with Kamal | Turn on branch protection for `main` (required review and passing checks) so the practice is enforced, not just followed, and so GitHub itself is the evidence |
| **CC9.1** Business disruption | Risks of disruption are identified and mitigated | RPO 5 minutes and RTO 30 minutes to 2 hours, with how each is met (RUNBOOK, Targets); tills keep selling offline | See Availability |
| **CC9.2** Vendors | Suppliers are assessed, under contract, and reviewed | The services are known and few | A vendor register: Contabo (servers, object storage), Cloudflare, AWS (SES), GitHub, Sentry, Africa's Talking, Safaricom, Airtel, Paystack, Meta (WhatsApp). For each: what data it sees, its own SOC 2 or ISO 27001 report on file, a data processing agreement, and a yearly review |

## Availability

| What the auditor wants to see | What HardPoint has | Gap |
|---|---|---|
| Capacity is monitored and planned | The admin Database page (connections, cache hit rates, sizes), disk checks in `PlatformHealth`, a load test and a scaling plan (perf/README.md, RUNBOOK §6) | Repeat the load test on the production VPS size (launch list) |
| Backups, tested | Continuous WAL shipping, hourly dumps, weekly base backups, all encrypted and off-site with a write-only key; each shop's own verified backups | Backups aren't running yet on a production server (launch list) |
| Recovery is tested | A drill procedure and log (RUNBOOK §3); dump-path drills done locally in September and November 2026 | The point-in-time restore (`restore_pitr.sh`) has never been run on a real server. Do it, time it, and keep doing it monthly: the drill log is the evidence |
| Commitments to customers | `/sla` | Publish a status page; keep uptime records to show the SLA was met |

## Confidentiality

| What the auditor wants to see | What HardPoint has | Gap |
|---|---|---|
| Confidential data is identified and protected | Each shop's data kept apart by Postgres row-level security on every tenant table, tested on every push; secrets encrypted; logs filtered of passwords, PINs, phone numbers and KRA PINs; staging is a scrambled copy | A one-page data classification (what counts as confidential, where it lives). Customer phone numbers and KRA PINs aren't encrypted column by column; the reason is recorded in docs/SECURITY.md and an auditor will want that as an accepted risk in the register |
| Data is disposed of when it should be | A closed shop is deleted after 30 days; exports and backups expire; sessions are purged nightly; bucket lifecycle rules for backups | A written retention schedule that matches what the code does |

## Not in scope for a first report

- **Processing Integrity:** would cover that sales, stock and tax are processed completely and accurately. The
  material exists (gap-free receipt numbers, idempotent payment callbacks, eTIMS retries), but it adds audit work
  for little sales value at this stage.
- **Privacy:** the Kenya Data Protection Act already applies and registration with the ODPC is on the launch list.
  SOC 2's Privacy criteria overlap with it heavily; do the ODPC work first and revisit.

## The policy set to write

Short documents, a page or two each, approved by a named person, reviewed yearly. Most only need to describe
what the code and runbook already do.

1. Information security policy (the umbrella: scope, roles, the security owner)
2. Access control (accounts, two-factor, joiners and leavers, the quarterly review)
3. Change management (pull requests, review, CI, staging, deploys, emergency changes)
4. Incident response (severities, roles, customer and regulator notification, post-incident review)
5. Backup, disaster recovery and business continuity (the RPO and RTO, the drill)
6. Risk management (the register and how it's reviewed)
7. Vendor management (the register, what's checked before a new supplier is used)
8. Data classification, retention and disposal
9. Acceptable use and code of conduct (laptops, passwords, reporting concerns)
10. Secure development (dependency updates, scanning, security review of risky changes)
11. Vulnerability management (how reports to security@ are handled, patching times by severity)
12. Encryption and key management (what's encrypted, where keys live, the quarterly rotation)

## Suggested order

1. **Finish docs/LAUNCH.md.** Nearly every unticked line there is also SOC 2 evidence: backups running, a real
   restore drill, monitoring and alerts, the external penetration test, the lawyer's review.
2. **Name a security owner and turn on branch protection.** Both take an hour and start the evidence trail.
3. **Write the policy set and the three registers** (risks, vendors, access reviews).
4. **Choose a compliance platform** (Vanta, Drata, Secureframe and the like collect evidence from GitHub, the
   cloud accounts and laptops automatically) **and an audit firm.** The platform's price usually bundles a list of
   firms. Ask for Security, Availability and Confidentiality.
5. **Type I** once the gaps above are closed, then start the **Type II** period straight away.

A realistic span from starting step 2 to holding a Type II report is 6 to 12 months, most of it the observation
period. Costs vary widely by firm and platform; get quotes rather than rely on a figure here.
