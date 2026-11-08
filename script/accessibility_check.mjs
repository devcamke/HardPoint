// Runs axe-core over HardPoint's main screens and fails on serious or critical accessibility violations, so a
// regression (a button without a name, an input without a label, unreadable contrast) is caught in CI rather
// than by a cashier. Needs the app running with the demo shop seeded (bin/setup in development; SEED_DEMO=1
// bin/rails db:seed:replant in test, as CI does), Playwright's Chromium, and axe-core:
//
//   npm install --no-save playwright axe-core && npx playwright install chromium
//   node script/accessibility_check.mjs
//
// Settings, from the environment: A11Y_SHOP_URL (default http://demo.localhost:3000), A11Y_SITE_URL (default
// http://localhost:3000), A11Y_EMAIL and A11Y_PASSWORD (the demo owner), A11Y_FAIL_ON (default serious,critical).
import { readFileSync } from "node:fs"
import { createRequire } from "node:module"

const require = createRequire(import.meta.url)
const { chromium } = require("playwright")
const axeSource = readFileSync(require.resolve("axe-core/axe.min.js"), "utf8")

const shopUrl = process.env.A11Y_SHOP_URL || "http://demo.localhost:3000"
const siteUrl = process.env.A11Y_SITE_URL || "http://localhost:3000"
const failOn = (process.env.A11Y_FAIL_ON || "serious,critical").split(",")

// The screens a shop lives in. Each is scanned as the demo owner, who sees everything.
const shopPages = [ "/", "/pos", "/products", "/customers", "/suppliers", "/purchase_orders", "/stock", "/reorder_list",
  "/reports", "/settings", "/memberships", "/my/profile", "/my/devices", "/account_data", "/orders", "/deliveries" ]
const sitePages = [ "/", "/pricing", "/signup/new", "/help", "/help/selling", "/terms", "/data-processing", "/sla", "/privacy" ]

// A page that can't be reached or scanned is itself a critical finding, so one broken page doesn't hide the rest.
async function scan(page, url, violations) {
  try {
    const response = await page.goto(url, { waitUntil: "networkidle" })
    if (!response || response.status() >= 400) { violations.push({ url, id: "http", impact: "critical", help: `answered ${response?.status()}`, nodes: [] }); return }
    await page.addScriptTag({ content: axeSource })
    const results = await page.evaluate(() => window.axe.run(document, { runOnly: { type: "tag", values: [ "wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "best-practice" ] } }))
    for (const violation of results.violations) {
      violations.push({ url, id: violation.id, impact: violation.impact, help: violation.help, nodes: violation.nodes.map((node) => node.target.join(" ")).slice(0, 5) })
    }
    process.stdout.write(`scanned ${url}: ${results.violations.length} findings\n`)
  } catch (error) {
    violations.push({ url, id: "scan", impact: "critical", help: `couldn't be scanned: ${error.message.split("\n")[0]}`, nodes: [] })
  }
}

const browser = await chromium.launch()
// The app's content security policy rightly refuses injected scripts; the scanner's own copy of axe is let through.
const context = await browser.newContext({ viewport: { width: 1280, height: 800 }, bypassCSP: true })
const page = await context.newPage()
const violations = []

for (const path of sitePages) await scan(page, siteUrl + path, violations)

try {
  await page.goto(`${shopUrl}/session/new`)
  await page.fill("input[name=email_address]", process.env.A11Y_EMAIL || "owner@demo.test")
  await page.fill("input[name=password]", process.env.A11Y_PASSWORD || "hardpoint-demo")
  await page.click("input[type=submit], button[type=submit]")
  await page.waitForURL((url) => !url.pathname.startsWith("/session"))
  for (const path of shopPages) await scan(page, shopUrl + path, violations)
} catch (error) {
  violations.push({ url: `${shopUrl}/session/new`, id: "sign-in", impact: "critical", help: `couldn't sign in to the demo shop (${await page.title()}): ${error.message.split("\n")[0]}`, nodes: [] })
}

await browser.close()

const failing = violations.filter((violation) => failOn.includes(violation.impact))
const byPage = Object.groupBy(violations, (violation) => violation.url)
for (const [ url, found ] of Object.entries(byPage)) {
  console.log(`\n${url}`)
  for (const violation of found) console.log(`  ${failOn.includes(violation.impact) ? "FAIL" : "note"} [${violation.impact}] ${violation.id}: ${violation.help}${violation.nodes.length ? ` (${violation.nodes.join("; ")})` : ""}`)
}
console.log(`\n${sitePages.length + shopPages.length} pages scanned, ${violations.length} findings, ${failing.length} ${failOn.join("/")}`)
process.exit(failing.length ? 1 : 0)
