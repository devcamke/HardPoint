import { Controller } from "@hotwired/stimulus"
import * as store from "offline/store"
import { unitPrice, saleTotals, lineTotals, formatMoney, formatQuantity, thousandths } from "offline/arithmetic"
import { printReceipt } from "offline/printer"

// The offline till: sells from the catalogue snapshot on this device while the network is down.
// Sales are kept on the device and sent by the offline-sync controller when it's back; they get
// their receipt numbers then. Cash, or a typed M-Pesa or card code (checked later against the
// M-Pesa reconciliation); no customers, accounts or discounts until the till is online.
export default class extends Controller {
  static targets = [ "code", "results", "quickPicks", "cart", "total", "tax", "items", "tendered", "reference", "referenceField",
                     "tenderedField", "change", "message", "queue", "completed", "receipt", "till", "snapshot", "payButton" ]

  connect() {
    this.cart = []
    this.load()
    this.renderQueue = this.renderQueue.bind(this)
    document.addEventListener("offline-sync:sent", this.renderQueue)
    document.addEventListener("offline-sync:catalogue", () => this.load())
    this.channel = "BroadcastChannel" in window ? new BroadcastChannel("hardpoint-display") : null
  }

  disconnect() {
    document.removeEventListener("offline-sync:sent", this.renderQueue)
    this.channel?.close()
  }

  async load() {
    this.catalogue = await store.catalogue.get()
    if (!this.catalogue) {
      this.show("This device hasn't had the till open online yet, so it has no catalogue to sell from. Open the till once while online.", "alert")
      this.payButtonTarget.disabled = true
      return
    }
    const till = this.catalogue.till
    this.tillTarget.textContent = `${till.register_name} · ${till.branch_name} · ${till.cashier_name}`
    this.snapshotTarget.textContent = `Prices as of ${new Date(this.catalogue.generated_at).toLocaleString("en-KE", { dateStyle: "medium", timeStyle: "short" })}`
    this.byCode = new Map()
    for (const product of this.catalogue.products) {
      for (const code of [ product.sku, ...product.barcodes ]) this.byCode.set(code.toUpperCase(), { product })
      for (const pack of product.packs) for (const code of pack.barcodes) this.byCode.set(code.toUpperCase(), { product, pack })
    }
    this.renderQuickPicks()
    this.render()
    this.renderQueue()
  }

  // A scanner types the code and presses Enter; a person types words to search.
  scan(event) {
    event.preventDefault()
    const code = this.codeTarget.value.trim()
    if (!code) return

    const found = this.byCode?.get(code.toUpperCase())
    if (found) {
      this.add(found.product, found.pack)
      this.codeTarget.value = ""
      this.resultsTarget.innerHTML = ""
    } else {
      this.search()
      if (!this.resultsTarget.children.length) this.show(`Nothing found for “${code}”`, "alert")
    }
  }

  search() {
    const words = this.codeTarget.value.trim().toLowerCase().split(/\s+/).filter(Boolean)
    if (!words.length || !this.catalogue) return (this.resultsTarget.innerHTML = "")

    const matches = this.catalogue.products.filter((product) => words.every((word) => `${product.name} ${product.sku}`.toLowerCase().includes(word))).slice(0, 12)
    this.resultsTarget.innerHTML = matches.map((product) => this.productButton(product)).join("")
  }

  pick(event) {
    const product = this.catalogue.products.find((candidate) => candidate.id === Number(event.currentTarget.dataset.productId))
    const pack = product.packs.find((candidate) => candidate.id === Number(event.currentTarget.dataset.packId))
    this.add(product, pack)
    this.codeTarget.focus()
  }

  add(product, pack = null) {
    const line = this.cart.find((candidate) => candidate.product.id === product.id && candidate.pack?.id === pack?.id)
    if (line) {
      line.quantity = Number(line.quantity) + 1
    } else {
      this.cart.push({ product, pack, quantity: 1 })
    }
    this.show("")
    this.render()
  }

  changeQuantity(event) {
    const line = this.cart[Number(event.target.dataset.index)]
    const quantity = Number(event.target.value)
    const whole = line.pack || !line.product.fractional
    if (!(quantity > 0) || (whole && !Number.isInteger(quantity))) {
      this.show(`Enter a ${whole ? "whole number" : "quantity"} for ${line.product.name}`, "alert")
      return this.render()
    }
    line.quantity = quantity
    this.render()
  }

  remove(event) {
    this.cart.splice(Number(event.currentTarget.dataset.index), 1)
    this.render()
  }

  clear() {
    this.cart = []
    this.render()
  }

  switchTender() {
    const tender = this.tender
    this.tenderedFieldTarget.hidden = tender !== "cash"
    this.referenceFieldTarget.hidden = tender === "cash"
    this.showChange()
  }

  showChange() {
    const tendered = Math.round(Number(this.tenderedTarget.value || 0) * 100)
    const change = tendered - this.totals.total
    this.changeTarget.textContent = this.tender === "cash" && tendered > 0 && change >= 0 ? `Change ${formatMoney(change, this.catalogue.till.currency)}` : ""
  }

  async pay(event) {
    event.preventDefault()
    if (!this.cart.length) return this.show("Add something to sell first", "alert")

    const till = this.catalogue.till
    const total = this.totals.total
    const tender = this.tender
    const tendered = tender === "cash" ? Math.round(Number(this.tenderedTarget.value || total / 100) * 100) : null
    const reference = this.referenceTarget.value.trim().toUpperCase()
    if (tender === "cash" && tendered < total) return this.show(`Cash received is less than the ${formatMoney(total, till.currency)} due`, "alert")
    if (tender !== "cash" && !reference) return this.show(`Enter the ${tender === "mobile_money" ? "M-Pesa" : "card"} code; it's checked once the till is back online`, "alert")

    const counter = await store.meta.next(`receipt-counter-${till.register_id}`)
    const receiptNumber = `${till.branch_code}-OFF${till.register_id}-${String(counter).padStart(4, "0")}`
    const happenedAt = new Date().toISOString()
    const uuid = crypto.randomUUID()
    const lines = this.pricedLines()
    const payment = { tender, amount_cents: tender === "cash" ? null : total, tendered_cents: tendered, reference: reference || null }

    const sale = {
      uuid, status: "waiting", happened_at: happenedAt, receipt_number: null, offline_receipt_number: receiptNumber, total_cents: total,
      payload: { uuid, receipt_number: receiptNumber, happened_at: happenedAt, shift_id: till.shift_id, cashier_id: till.cashier_id,
                 total_cents: total, discount_cents: 0, payments: [ payment ],
                 lines: lines.map((line) => ({ product_id: line.product.id, product_unit_id: line.pack?.id ?? null, quantity: String(line.quantity),
                                               unit_price_cents: line.unit_price_cents, discount_cents: 0 })) },
      receipt: this.receiptData(receiptNumber, lines, payment)
    }
    await store.sales.put(sale)
    document.dispatchEvent(new CustomEvent("offline-till:queued"))

    this.lastReceipt = sale.receipt
    this.cart = []
    this.tenderedTarget.value = ""
    this.referenceTarget.value = ""
    this.codeTarget.value = ""
    this.resultsTarget.innerHTML = ""
    this.element.querySelector("input[name=tender][value=cash]").checked = true
    this.switchTender()
    this.render()
    this.renderQueue()
    this.completedTarget.hidden = false
    this.completedTarget.querySelector("[data-role=summary]").textContent =
      `Sale ${receiptNumber} saved on this till · ${formatMoney(total, till.currency)}` + (tendered > total ? ` · Change ${formatMoney(tendered - total, till.currency)}` : "")
    this.channel?.postMessage({ status: "complete", total: formatMoney(total, till.currency), change: tendered > total ? formatMoney(tendered - total, till.currency) : null })
    this.print()
  }

  async print() {
    if (!this.lastReceipt) return
    const till = this.catalogue.till
    if (till.print_mode === "qz_tray") {
      try {
        return await printReceipt(this.lastReceipt, till)
      } catch (error) {
        this.show(`Couldn't print through QZ Tray (${error.message}); printing through the browser instead.`, "alert")
      }
    }
    this.receiptTarget.innerHTML = this.receiptHtml(this.lastReceipt)
    window.print()
  }

  newSale() {
    this.completedTarget.hidden = true
    this.codeTarget.focus()
  }

  // Everything below is display.

  get tender() {
    return this.element.querySelector("input[name=tender]:checked")?.value || "cash"
  }

  pricedLines() {
    return this.cart.map((line) => {
      const taxRate = line.product.tax_rate
      const unitPriceCents = unitPrice(line.product, line.pack, line.quantity)
      return { ...line, unit_price_cents: unitPriceCents, tax_rate: taxRate, ...lineTotals({ unit_price_cents: unitPriceCents, quantity: line.quantity, tax_rate: taxRate }) }
    })
  }

  render() {
    if (!this.catalogue) return
    const currency = this.catalogue.till.currency
    const lines = this.pricedLines()
    this.totals = saleTotals(lines)

    this.cartTarget.innerHTML = lines.length ? lines.map((line, index) => `
      <li class="px-4 py-3">
        <div class="flex items-start justify-between gap-2">
          <div class="min-w-0"><p class="font-medium">${escape(line.product.name)}${line.pack ? ` <span class="text-steel-600">(${escape(line.pack.name)})</span>` : ""}</p>
            <p class="text-xs text-steel-600">${formatMoney(line.unit_price_cents, currency)} / ${escape(line.pack?.unit || line.product.unit)}</p></div>
          <p class="whitespace-nowrap font-semibold tabular-nums">${formatMoney(line.total, currency)}</p>
        </div>
        <div class="mt-1 flex items-center justify-between">
          <input type="number" min="0" step="${line.pack || !line.product.fractional ? 1 : "any"}" value="${line.quantity}" data-index="${index}"
                 data-action="change->offline-till#changeQuantity" class="input w-24 py-1 text-right" aria-label="Quantity of ${escape(line.product.name)}">
          <button type="button" data-index="${index}" data-action="offline-till#remove" class="text-steel-500 hover:text-red-700" aria-label="Remove ${escape(line.product.name)}">✕</button>
        </div>
      </li>`).join("") : `<li class="p-8 text-center text-steel-600">Scan or tap products to start a sale.</li>`

    this.itemsTarget.textContent = formatQuantity(lines.reduce((sum, line) => sum + thousandths(line.quantity), 0) / 1000)
    this.taxTarget.textContent = formatMoney(this.totals.tax, currency)
    this.totalTarget.textContent = formatMoney(this.totals.total, currency)
    this.tenderedTarget.placeholder = (this.totals.total / 100).toFixed(2)
    this.showChange()
    this.channel?.postMessage({ status: lines.length ? "cart" : "idle", total: formatMoney(this.totals.total, currency), paybill: this.catalogue.till.paybill,
      lines: lines.map((line) => ({ description: line.product.name + (line.pack ? ` (${line.pack.name})` : ""), quantity: formatQuantity(line.quantity), total: formatMoney(line.total) })) })
  }

  renderQuickPicks() {
    const picks = this.catalogue.products.filter((product) => product.quick_pick).slice(0, 16)
    this.quickPicksTarget.innerHTML = picks.map((product) => this.productButton(product, true)).join("")
  }

  productButton(product, large = false) {
    const currency = this.catalogue.till.currency
    const stock = product.stock === null ? "" : `<span class="block text-xs ${product.stock > 0 ? "text-steel-600" : "text-red-700"}">${formatQuantity(product.stock)} ${escape(product.unit)} at last sync</span>`
    const packs = product.packs.map((pack) => `<button type="button" data-action="offline-till#pick" data-product-id="${product.id}" data-pack-id="${pack.id}"
        class="mt-2 w-full rounded border border-concrete-300 px-2 py-1 text-xs font-semibold hover:border-safety-400">${escape(pack.unit)} · ${formatMoney(pack.price_cents, currency)}</button>`).join("")
    return `<div class="card ${large ? "p-3" : "p-2"} text-left">
      <button type="button" data-action="offline-till#pick" data-product-id="${product.id}" class="w-full text-left">
        <span class="block font-medium">${escape(product.name)}</span>
        <span class="block ${large ? "text-lg" : ""} font-bold tabular-nums">${formatMoney(product.price_cents, currency)}</span>${stock}
      </button>${packs}</div>`
  }

  async renderQueue() {
    const sales = (await store.sales.all()).sort((a, b) => b.happened_at.localeCompare(a.happened_at)).slice(0, 12)
    const currency = this.catalogue?.till.currency || ""
    this.queueTarget.innerHTML = sales.length ? sales.map((sale) => `
      <li class="flex items-start justify-between gap-3 py-2 text-sm">
        <span><span class="font-mono">${escape(sale.receipt_number || sale.offline_receipt_number)}</span>
          <span class="block text-xs text-steel-600">${new Date(sale.happened_at).toLocaleTimeString("en-KE", { timeStyle: "short" })}
          ${sale.status === "sent" ? `· sent${sale.receipt_number ? ` (was ${escape(sale.offline_receipt_number)})` : ""}` : ""}</span>
          ${(sale.warnings || []).map((warning) => `<span class="block text-xs text-safety-800">${escape(warning)}</span>`).join("")}
          ${sale.error ? `<span class="block text-xs text-red-700">${escape(sale.error)}</span>` : ""}</span>
        <span class="whitespace-nowrap text-right tabular-nums">${formatMoney(sale.total_cents, currency)}
          <span class="badge ${{ sent: "bg-green-50 text-green-800", error: "bg-red-50 text-red-800" }[sale.status] || "bg-safety-100 text-safety-800"}">${{ sent: "Sent", error: "Problem" }[sale.status] || "Waiting"}</span></span>
      </li>`).join("") : `<li class="py-2 text-sm text-steel-600">No offline sales on this till.</li>`
  }

  receiptData(receiptNumber, lines, payment) {
    const till = this.catalogue.till
    const change = payment.tender === "cash" ? payment.tendered_cents - this.totals.total : 0
    const labels = { cash: "Cash", mobile_money: "M-Pesa", card: "Card" }
    return {
      header: [ till.account_name, till.branch_name, till.branch_address, till.branch_phone && `Tel ${till.branch_phone}` ].filter(Boolean),
      receipt_number: receiptNumber, time: new Date().toLocaleString("en-KE", { dateStyle: "medium", timeStyle: "short" }), register: till.register_name,
      cashier: till.cashier_name, offline: true,
      lines: lines.map((line) => ({ description: line.product.name + (line.pack ? ` (${line.pack.name})` : ""),
                                    detail: `${formatQuantity(line.quantity)} ${line.pack?.unit || line.product.unit} x ${formatMoney(line.unit_price_cents)}`, total: formatMoney(line.total) })),
      total: formatMoney(this.totals.total, till.currency), tax: formatMoney(this.totals.tax, till.currency),
      payments: [ { label: [ labels[payment.tender], payment.reference ].filter(Boolean).join(" "), amount: formatMoney(payment.tendered_cents ?? payment.amount_cents, till.currency) } ],
      change: change > 0 ? formatMoney(change, till.currency) : null,
      footer: till.receipt_footer || "Thank you for shopping with us", open_drawer: payment.tender === "cash"
    }
  }

  receiptHtml(data) {
    const row = (left, right, classes = "") => `<div class="row ${classes}"><span>${escape(left)}</span><span>${escape(right)}</span></div>`
    return `<div class="receipt">
      <p class="center bold big">${escape(data.header[0])}</p><p class="center">${data.header.slice(1).map(escape).join("<br>")}</p><hr>
      ${row("Receipt", data.receipt_number, "bold")}${row(data.time, data.register)}${row("Served by", data.cashier)}
      <p class="center">Recorded offline; sent when the till is back online.</p><hr>
      ${data.lines.map((line) => `<div class="item"><div>${escape(line.description)}</div>${row(line.detail, line.total, "muted")}</div>`).join("")}<hr>
      ${row("TOTAL", data.total, "bold big")}${row("Incl. tax", data.tax, "muted")}<hr>
      ${data.payments.map((payment) => row(payment.label, payment.amount)).join("")}${data.change ? row("Change", data.change, "bold") : ""}<hr>
      <p class="center">${escape(data.footer)}</p></div>`
  }

  show(text, kind = "notice") {
    this.messageTarget.textContent = text
    this.messageTarget.hidden = !text
    this.messageTarget.className = kind === "alert" ? "mb-3 rounded-md bg-red-50 px-4 py-2 text-sm text-red-800" : "mb-3 rounded-md bg-green-50 px-4 py-2 text-sm text-green-800"
  }
}

function escape(value) {
  return String(value ?? "").replace(/[&<>"']/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[character])
}
