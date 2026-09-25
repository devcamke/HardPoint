// The till's sums, done exactly as the server does them (Sale::Cart, SaleLine), so an offline
// sale adds up to the same total when it's recorded. Money is whole cents; quantities are
// handled in thousandths so decimal kilograms and metres don't pick up floating-point dust.

export function thousandths(quantity) {
  return Math.round(Number(quantity) * 1000)
}

// The unit price that applies at this quantity (Product#price_cents_for): the lowest of the retail
// price, any retail quantity break reached and, for a customer on a price list, that list's prices
// reached (listPrices: [ [ minimum, price ] ] for this product). Packs have their own price.
export function unitPrice(product, pack, quantity, listPrices = []) {
  if (pack) return pack.price_cents
  const reached = [ ...(product.breaks || []), ...listPrices ].filter(([ minimum ]) => thousandths(quantity) >= thousandths(minimum)).map(([ , price ]) => price)
  return Math.min(product.price_cents, ...reached)
}

// What one promotion takes off a line (Promotion#saving_cents): a percentage comes off the shelf
// price, so a customer whose own price is lower gets whichever is better; free items are at their price.
export function promotionSaving(promotion, product, pack, quantity, unitPriceCents) {
  const covered = promotion.product_ids.includes(product.id) || (product.category_id != null && promotion.category_ids.includes(product.category_id))
  if (!covered || !(thousandths(quantity) > 0)) return 0

  if (promotion.kind === "percent_off") {
    const shelf = pack ? pack.price_cents : product.price_cents
    const offerPrice = Math.round(shelf * (100 - promotion.percent_off) / 100)
    return Math.max(Math.round((unitPriceCents - offerPrice) * thousandths(quantity) / 1000), 0)
  }
  const bundles = Math.floor(thousandths(quantity) / thousandths(promotion.buy_quantity + promotion.free_quantity))
  return Math.round(unitPriceCents * bundles * thousandths(promotion.free_quantity) / 1000)
}

// The promotion running on this day (YYYY-MM-DD) that saves most, or null (SaleLine#apply_best_promotion).
export function bestPromotion(promotions, day, product, pack, quantity, unitPriceCents) {
  let best = null
  for (const promotion of promotions || []) {
    if (promotion.starts_on > day || promotion.ends_on < day) continue
    const saving = promotionSaving(promotion, product, pack, quantity, unitPriceCents)
    if (saving > 0 && (!best || saving > best.saving)) best = { promotion, saving }
  }
  return best
}

// Today's date where the shop is, as the server counts days.
export function localDay(timeZone, now = new Date()) {
  return now.toLocaleDateString("en-CA", { timeZone })
}

export function lineTotals(line) {
  const gross = Math.round(line.unit_price_cents * thousandths(line.quantity) / 1000)
  const total = gross - (line.discount_cents || 0) - (line.promotion_discount_cents || 0)
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
