// The till's sums, done exactly as the server does them (Sale::Cart, SaleLine), so an offline
// sale adds up to the same total when it's recorded. Money is whole cents; quantities are
// handled in thousandths so decimal kilograms and metres don't pick up floating-point dust.

export function thousandths(quantity) {
  return Math.round(Number(quantity) * 1000)
}

// The unit price that applies at this quantity: the lowest of the retail price and any retail
// quantity break reached (packs have their own price).
export function unitPrice(product, pack, quantity) {
  if (pack) return pack.price_cents
  const breaks = (product.breaks || []).filter(([ minimum ]) => thousandths(quantity) >= thousandths(minimum)).map(([ , price ]) => price)
  return Math.min(product.price_cents, ...breaks)
}

export function lineTotals(line) {
  const gross = Math.round(line.unit_price_cents * thousandths(line.quantity) / 1000)
  const total = gross - (line.discount_cents || 0)
  const tax = Math.round(total * line.tax_rate / (100 + line.tax_rate))
  return { gross, total, tax }
}

export function saleTotals(lines, discountCents = 0) {
  const totals = lines.map(lineTotals)
  const subtotal = totals.reduce((sum, line) => sum + line.total, 0)
  const discount = Math.min(Math.max(discountCents, 0), subtotal)
  const total = subtotal - discount
  const lineTax = totals.reduce((sum, line) => sum + line.tax, 0)
  const tax = subtotal === 0 ? 0 : Math.round(lineTax * total / subtotal)
  return { subtotal, discount, total, tax }
}

export function formatMoney(cents, currency = "") {
  const amount = (cents / 100).toLocaleString("en-KE", { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  return currency ? `${currency} ${amount}` : amount
}

export function formatQuantity(quantity) {
  return Number(quantity).toLocaleString("en-KE", { maximumFractionDigits: 3 })
}
