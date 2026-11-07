// Takes the screenshot for each guided tour and measures where each step's target is on it. Run through
// `bin/rails help:screenshots`, which passes the tours in and writes config/help_tour_hotspots.json from the output.
//
//   node script/help_screenshots.mjs <tours.json> <images directory> <hotspots.json>
//
// Needs the app running with the demo shop seeded (bin/setup, then bin/dev), and Playwright with its Chromium
// (npm install --no-save playwright && npx playwright install chromium). Settings, from the environment:
//   HELP_SHOP_URL   default http://demo.localhost:3000
//   HELP_EMAIL      default owner@demo.test
//   HELP_PASSWORD   default hardpoint-demo
import { readFileSync, writeFileSync, mkdirSync } from "node:fs"
import { createRequire } from "node:module"
import { join } from "node:path"

const require = createRequire(import.meta.url)
const { chromium } = require("playwright")

const [ toursPath, imagesDirectory, hotspotsPath ] = process.argv.slice(2)
const tours = JSON.parse(readFileSync(toursPath, "utf8"))
const shopUrl = process.env.HELP_SHOP_URL || "http://demo.localhost:3000"
const viewport = { width: 1280, height: 800 }

// Gets a screen into a state worth showing before its screenshot. Each tour starts on its start page.
const prepare = {
  // Leave out the setup checklist and the two-factor reminder: they're about the demo owner, not the screen.
  async home(page) {
    await page.evaluate(() => {
      document.getElementById("onboarding_card")?.remove()
      document.querySelector("main a[href*='two_factor']")?.closest("div.border")?.remove()
    })
  },
  // The till needs a till chosen with a shift open, and a sale with something in it.
  async till(page) {
    if (page.url().includes("/pos/till")) {
      await page.locator("a, button", { hasText: /shift open/ }).first().click()
      await page.waitForURL(/\/pos$/)
    }
    await page.locator("[data-tour=categories]").waitFor()
    const lines = page.locator("[data-tour=lines] li")
    const buttons = page.locator("#search_results form button[type=submit], #search_results button[type=submit]")
    for (const index of [ 0, 2 ]) {
      if (await lines.count() >= 2) break
      await buttons.nth(index).click()
      await page.waitForTimeout(800)
    }
    await page.locator("[data-tour=take-payment]").waitFor()
  },
  // From the list of stock takes, into one that's being counted.
  async "stock-take"(page) {
    await page.locator("tr", { hasText: "Counting" }).first().locator("a").first().click()
    await page.locator("[data-tour=count-scan]").waitFor()
  },
  // From Receiving, Receive on the first order waiting for delivery.
  async receiving(page) {
    await page.getByRole("link", { name: "Receive", exact: true }).first().click()
    await page.locator("[data-tour=receive-lines]").waitFor()
  },
  // From the till (chosen by the till's tour), Shift at the top, then Close shift.
  async "close-shift"(page) {
    await page.locator("header").getByRole("link", { name: "Shift", exact: true }).click()
    await page.getByRole("link", { name: "Close shift", exact: true }).click()
    await page.locator("[data-tour=close-cash]").waitFor()
  },
  // A customer who owes something, so their account has numbers in it: the first on Who owes us.
  async customer(page) {
    await page.goto(new URL("/receivables", page.url()).href)
    await page.locator("main a[href^='/customers/']").first().click()
    await page.locator("[data-tour=customer-account]").waitFor()
  }
}

const browser = await chromium.launch()
const context = await browser.newContext({ viewport, deviceScaleFactor: 2 })
const page = await context.newPage()

await page.goto(`${shopUrl}/session/new`)
await page.fill("#email_address", process.env.HELP_EMAIL || "owner@demo.test")
await page.fill("#password", process.env.HELP_PASSWORD || "hardpoint-demo")
await Promise.all([ page.waitForURL((url) => !url.pathname.startsWith("/session")), page.click("input[type=submit]") ])

mkdirSync(imagesDirectory, { recursive: true })
const hotspots = {}

for (const tour of tours) {
  await page.goto(shopUrl + tour.page)
  await page.waitForLoadState("networkidle")
  await prepare[tour.id]?.(page)
  // Leave out announcements and the blinking caret, and close anything left open.
  await page.addStyleTag({ content: "[id^=announcement_]{display:none!important} *{caret-color:transparent!important}" })
  await page.evaluate(() => document.activeElement?.blur())
  await page.mouse.move(0, viewport.height - 1)
  await page.waitForTimeout(400)

  const steps = {}
  for (const target of tour.targets) {
    const element = page.locator(`[data-tour="${target}"]`).first()
    const box = (await element.count()) && await element.isVisible() ? await element.boundingBox() : null
    if (!box) { console.warn(`${tour.id}: ${target} isn't on the screen`); continue }
    const percent = (value, of) => Math.round(Math.min(Math.max(value / of, 0), 1) * 1000) / 10
    const left = Math.max(box.x, 0), top = Math.max(box.y, 0)
    steps[target] = [ percent(left, viewport.width), percent(top, viewport.height),
      percent(Math.min(box.x + box.width, viewport.width) - left, viewport.width),
      percent(Math.min(box.y + box.height, viewport.height) - top, viewport.height) ]
  }

  await page.screenshot({ path: join(imagesDirectory, `${tour.id}.png`) })
  hotspots[tour.id] = { size: [ viewport.width, viewport.height ], steps }
  console.log(`${tour.id}: ${Object.keys(steps).length} of ${tour.targets.length} steps placed`)
}

await browser.close()
// One line per step, so a change to a screen reads well in a diff.
writeFileSync(hotspotsPath, JSON.stringify(hotspots, null, 2).replace(/\[\s+([\d.,\s]+?)\s+\]/g, (_, numbers) => `[ ${numbers.split(/,\s*/).join(", ")} ]`) + "\n")
