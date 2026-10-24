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
function covers(promotion, product) {
  return promotion.product_ids.includes(product.id) || (product.category_id != null && promotion.category_ids.includes(product.category_id))
}

export function promotionSaving(promotion, product, pack, quantity, unitPriceCents) {
  if (promotion.kind === "bundle" || !covers(promotion, product) || !(thousandths(quantity) > 0)) return 0

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

// What a mix-and-match bundle takes off the lines given (Promotion#bundle_savings): a Map of line
// index => cents, empty if no bundle is complete or it saves nothing. Dearest units fill the bundles;
// the saving is shared by what each line's bundled units cost, odd cents to the biggest contributors.
// Lines are { product, pack, quantity, unit_price_cents }.
export function bundleSavings(promotion, lines, indexes = lines.map((_, index) => index)) {
  const eligible = indexes.filter((index) => covers(promotion, lines[index].product))
  const wholeUnits = (index) => Math.floor(thousandths(lines[index].quantity) / 1000)
  const bundles = Math.floor(eligible.reduce((sum, index) => sum + wholeUnits(index), 0) / promotion.bundle_quantity)
  const shares = new Map()
  if (bundles === 0) return shares

  let left = bundles * promotion.bundle_quantity
  const taken = []
  eligible.map((index, order) => ({ index, order })).sort((a, b) => lines[b.index].unit_price_cents - lines[a.index].unit_price_cents || a.order - b.order)
    .forEach(({ index }) => {
      const take = Math.min(wholeUnits(index), left)
      left -= take
      if (take > 0) taken.push({ index, cost: take * lines[index].unit_price_cents })
    })
  const value = taken.reduce((sum, { cost }) => sum + cost, 0)
  const saving = value - bundles * promotion.bundle_price_cents
  if (saving <= 0) return shares

  taken.forEach(({ index, cost }) => shares.set(index, Math.floor(saving * cost / value)))
  const odd = saving - [ ...shares.values() ].reduce((sum, cents) => sum + cents, 0)
  taken.map((entry, order) => ({ ...entry, order })).sort((a, b) => b.cost - a.cost || a.order - b.order).slice(0, odd)
    .forEach(({ index }) => shares.set(index, shares.get(index) + 1))
  return shares
}

// Bundles running on this day, oldest first, over lines already given their own best promotion
// ({ promotion, promotion_discount_cents }), as Sale::Bundles does: a bundle takes the lines it covers
// when it saves more than their own promotions. Returns the lines with promotions changed.
export function applyBundles(promotions, day, lines) {
  const result = lines.map((line) => ({ ...line }))
  const claimed = new Set()
  const bundles = (promotions || []).filter((promotion) => promotion.kind === "bundle" && promotion.starts_on <= day && promotion.ends_on >= day)
  bundles.sort((a, b) => a.id - b.id).forEach((promotion) => {
    const open = result.map((line, index) => index).filter((index) => !claimed.has(index) && !result[index].pack && thousandths(result[index].quantity) >= 1000)
    const shares = bundleSavings(promotion, result, open)
    const bundled = [ ...shares.values() ].reduce((sum, cents) => sum + cents, 0)
    const own = [ ...shares.keys() ].reduce((sum, index) => sum + (result[index].promotion_discount_cents || 0), 0)
    if (shares.size === 0 || bundled <= own) return

    shares.forEach((cents, index) => { result[index] = { ...result[index], promotion, promotion_discount_cents: cents }; claimed.add(index) })
  })
  return result
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
