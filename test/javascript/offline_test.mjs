// The offline till's arithmetic and receipt printing, run with Node's own test runner:
//   node --test test/javascript/
import { test } from "node:test"
import assert from "node:assert/strict"
import { unitPrice, lineTotals, saleTotals, thousandths, promotionSaving, bestPromotion, bundleSavings, applyBundles, pointsPayment, localDay } from "../../app/javascript/offline/arithmetic.js"
import { receipt, columns, wrap, ascii, commands } from "../../app/javascript/offline/escpos.js"

test("line and sale totals match the server's (SaleLine, Sale::Cart)", () => {
  // 4 kg at 250.00, 16% VAT included: the tax is the tax-inclusive share, rounded.
  assert.deepEqual(lineTotals({ unit_price_cents: 25000, quantity: 4, tax_rate: 16 }), { gross: 100000, total: 100000, tax: 13793 })
  // Decimal quantities without floating-point dust: 0.1 + 0.2 kg at 3.20 is exactly 0.96.
  assert.equal(lineTotals({ unit_price_cents: 320, quantity: 0.1 + 0.2, tax_rate: 16 }).total, 96)
  assert.equal(thousandths(0.1 + 0.2), 300)
  // Tax on a discounted sale is scaled down with the total.
  assert.deepEqual(saleTotals([ { unit_price_cents: 80000, quantity: 2, tax_rate: 16 } ], 16000), { subtotal: 160000, discount: 16000, total: 144000, tax: 19862 })
  assert.deepEqual(saleTotals([]), { subtotal: 0, discount: 0, total: 0, tax: 0 })
})

test("retail quantity breaks and pack prices", () => {
  const cement = { price_cents: 85000, breaks: [ [ 100, 83000 ] ] }
  assert.equal(unitPrice(cement, null, 99), 85000)
  assert.equal(unitPrice(cement, null, 100), 83000)
  assert.equal(unitPrice(cement, { price_cents: 85000 * 10 }, 1), 850000)
})

test("receipts in ESC/POS fit the paper, stay ASCII, cut, and open the drawer for cash", () => {
  assert.equal(columns("Portland cement 50kg (Bamburi) extra long", "1,700.00", 32).length, 32)
  assert.ok(wrap("Tile adhesive 20kg for wet areas and swimming pools", 20).every((line) => line.length <= 20))
  assert.equal(ascii("2 × ½ kg – café"), "2 x 1/2 kg - cafe")

  const data = { header: [ "Demo Hardware", "Moi Avenue" ], receipt_number: "MAI-000123", time: "24 Sep 14:05", register: "Front counter",
                 lines: [ { description: "Wire nails 4 inch", detail: "2 kg x 250.00", total: "500.00" } ], total: "KES 500.00", tax: "KES 68.97",
                 payments: [ { label: "Cash", amount: "KES 1,000.00" } ], change: "KES 500.00", footer: "Thank you", open_drawer: true }
  const bytes = [ ...receipt(data, { width: 32 }) ]
  const text = String.fromCharCode(...bytes)
  assert.deepEqual(bytes.slice(0, 2), commands.init)
  assert.match(text, /MAI-000123/)
  assert.ok(text.split("\n").every((line) => line.replace(/[\x00-\x1f]/g, "").length <= 32 + 8))
  assert.deepEqual(bytes.slice(-commands.openDrawer.length), commands.openDrawer)
  assert.ok(!String.fromCharCode(...receipt({ ...data, open_drawer: false })).includes(String.fromCharCode(...commands.openDrawer)))
})

// The same cases as test/models/promotion_test.rb, so the offline till and the server agree.
test("price lists: the lowest of retail, retail breaks and the customer's list", () => {
  const cement = { id: 1, price_cents: 80000, breaks: [ [ 100, 78000 ] ] }
  assert.equal(unitPrice(cement, null, 2, [ [ 1, 76000 ] ]), 76000)
  assert.equal(unitPrice(cement, null, 2, [ [ 50, 70000 ] ]), 80000, "a list break not reached yet")
  assert.equal(unitPrice(cement, null, 100, [ [ 1, 79000 ] ]), 78000)
})

test("promotions: buy ten get one free, a percentage, the best one, and the dates", () => {
  const cement = { id: 1, category_id: 7, price_cents: 80000 }
  const nails = { id: 2, category_id: 8, price_cents: 25000 }
  const deal = { id: 10, kind: "buy_get", buy_quantity: 10, free_quantity: 1, product_ids: [ 1 ], category_ids: [], starts_on: "2026-09-20", ends_on: "2026-09-30" }
  assert.equal(promotionSaving(deal, cement, null, 10, 80000), 0, "ten bags: nothing free yet")
  assert.equal(promotionSaving(deal, cement, null, 22, 80000), 2 * 80000)
  assert.equal(promotionSaving(deal, nails, null, 22, 25000), 0, "not covered")

  const tenOff = { id: 11, kind: "percent_off", percent_off: 10, product_ids: [], category_ids: [ 7 ], starts_on: "2026-09-20", ends_on: "2026-09-30" }
  assert.equal(promotionSaving(tenOff, cement, null, 2, 80000), 2 * 8000)
  assert.equal(promotionSaving(tenOff, cement, null, 2, 76000), 2 * 4000, "contractor price 760, offer 720: only the difference")
  assert.equal(promotionSaving(tenOff, cement, null, 2, 70000), 0, "their own price is already better")
  assert.equal(promotionSaving(tenOff, cement, null, 0.5, 80000), 4000, "decimal quantities")

  const twenty = { ...tenOff, id: 12, percent_off: 20 }
  assert.equal(bestPromotion([ tenOff, twenty ], "2026-09-25", cement, null, 1, 80000).promotion, twenty)
  assert.equal(bestPromotion([ { ...tenOff, id: 13, percent_off: 5 }, deal ], "2026-09-25", cement, null, 22, 80000).promotion, deal, "22 bags: 2 free (1,600) beats 5% off (880)")
  assert.equal(bestPromotion([ deal, twenty ], "2026-09-25", cement, null, 22, 80000).promotion, twenty, "but not 20% off (3,520)")
  assert.equal(bestPromotion([ twenty ], "2026-10-01", cement, null, 1, 80000), null, "ended")
  assert.equal(bestPromotion([ twenty ], "2026-09-19", cement, null, 1, 80000), null, "not started")

  assert.deepEqual(lineTotals({ unit_price_cents: 80000, quantity: 22, tax_rate: 16, promotion_discount_cents: 160000 }), { gross: 1760000, total: 1600000, tax: 220690 })
  assert.equal(localDay("Africa/Nairobi", new Date("2026-09-24T22:30:00Z")), "2026-09-25", "the shop's day, not UTC's")
})

// The same cases as the mix-and-match tests in test/models/promotion_test.rb.
test("bundles: any three for a price across lines, dearest first, shared by cost, only when it beats the lines' own", () => {
  const pipe = { id: 4, category_id: 9, price_cents: 120000 }
  const kit = { id: 5, category_id: 9, price_cents: 250000 }
  const three = { id: 20, kind: "bundle", bundle_quantity: 3, bundle_price_cents: 400000, product_ids: [], category_ids: [ 9 ], starts_on: "2026-10-01", ends_on: "2026-10-31" }
  const sorted = (shares) => [ ...shares ].sort((a, b) => a[0] - b[0])
  const line = (product, quantity) => ({ product, pack: null, quantity, unit_price_cents: product.price_cents, promotion: null, promotion_discount_cents: 0 })

  assert.equal(bundleSavings(three, [ line(pipe, 2) ]).size, 0, "two isn't a bundle")
  assert.deepEqual(sorted(bundleSavings(three, [ line(pipe, 2), line(kit, 1) ])), [ [ 0, 44081 ], [ 1, 45919 ] ])
  assert.deepEqual(sorted(bundleSavings(three, [ line(pipe, 4), line(kit, 1) ])), [ [ 0, 44081 ], [ 1, 45919 ] ], "five units: the kit and two pipes")
  assert.equal([ ...bundleSavings(three, [ line(pipe, 5), line(kit, 1) ]).values() ].reduce((a, b) => a + b), 2 * 120000 + 250000 + 3 * 120000 - 800000)
  assert.equal(bundleSavings(three, [ line(pipe, 5) ]).size, 0, "three pipes cost less than the bundle")
  assert.equal(promotionSaving(three, pipe, null, 3, 120000), 0, "no saving line by line")

  const lines = applyBundles([ three ], "2026-10-24", [ line(pipe, 2), line(kit, 1) ])
  assert.deepEqual(lines.map((l) => [ l.promotion?.id, l.promotion_discount_cents ]), [ [ 20, 44081 ], [ 20, 45919 ] ])
  assert.equal(saleTotals(lines.map((l) => ({ ...l, tax_rate: 16 }))).total, 400000)
  assert.equal(applyBundles([ three ], "2026-11-01", [ line(pipe, 2), line(kit, 1) ])[0].promotion, null, "ended")

  const thirty = { id: 21, kind: "percent_off", percent_off: 30 }
  const own = [ { ...line(pipe, 2), promotion: thirty, promotion_discount_cents: 72000 }, { ...line(kit, 1), promotion: thirty, promotion_discount_cents: 75000 } ]
  assert.deepEqual(applyBundles([ three ], "2026-10-24", own).map((l) => l.promotion.id), [ 21, 21 ], "1,470 off line by line beats 900")
  assert.equal(applyBundles([ three ], "2026-10-24", [ line(pipe, 2), { ...line(kit, 1), pack: { price_cents: 250000 } } ])[0].promotion, null, "packs stay out")
})

// The same rules as Sale::Payable#spend_points (test/models/loyalty_test.rb).
test("points: whole points, rounded up, capped by what's due and the balance, from the minimum", () => {
  const loyalty = { point_value_cents: 50, min_redeem_points: 20 }
  assert.equal(pointsPayment(loyalty, 19, 100000), null, "below the minimum")
  assert.equal(pointsPayment(null, 500, 100000), null, "no scheme")
  assert.deepEqual(pointsPayment(loyalty, 32, 100000), { points: 32, amount_cents: 1600 }, "all 32 points, worth 16.00")
  assert.deepEqual(pointsPayment(loyalty, 5000, 1025), { points: 21, amount_cents: 1025 }, "10.25 due: 21 points, never more than due")
  assert.equal(pointsPayment(loyalty, 500, 0), null, "nothing due")
})
