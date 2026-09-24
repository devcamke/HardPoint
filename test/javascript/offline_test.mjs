// The offline till's arithmetic and receipt printing, run with Node's own test runner:
//   node --test test/javascript/
import { test } from "node:test"
import assert from "node:assert/strict"
import { unitPrice, lineTotals, saleTotals, thousandths } from "../../app/javascript/offline/arithmetic.js"
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
