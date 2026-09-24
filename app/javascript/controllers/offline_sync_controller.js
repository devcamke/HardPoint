import { Controller } from "@hotwired/stimulus"
import * as store from "offline/store"

// On every till page: keeps the device ready to sell offline (service worker, the offline till page,
// the catalogue snapshot), sends sales rung up offline once the server can be reached, and shows
// whether the till is online and how many sales are waiting.
export default class extends Controller {
  static targets = [ "status", "banner" ]
  static values = { catalogueUrl: String, salesUrl: String, tokenUrl: String, offlineUrl: String, tillUrl: String, offlinePage: Boolean }

  static CATALOGUE_MAX_AGE = 5 * 60 * 1000
  static KEEP_SENT = 30

  connect() {
    this.update = this.update.bind(this)
    window.addEventListener("online", this.update)
    window.addEventListener("offline", this.update)
    document.addEventListener("offline-till:queued", this.update)
    this.timer = setInterval(this.update, 20000)
    this.prepareDevice()
    this.update()
  }

  disconnect() {
    window.removeEventListener("online", this.update)
    window.removeEventListener("offline", this.update)
    document.removeEventListener("offline-till:queued", this.update)
    clearInterval(this.timer)
  }

  async prepareDevice() {
    if (!("serviceWorker" in navigator) || !navigator.onLine) return

    await navigator.serviceWorker.register("/service-worker.js")
    const { active } = await navigator.serviceWorker.ready
    // Keep a fresh copy of the offline till and everything it loads.
    if (!this.offlinePageValue) active?.postMessage({ type: "cache", urls: [ this.offlineUrlValue, ...this.assetUrls() ] })
  }

  assetUrls() {
    const importmap = JSON.parse(document.querySelector("script[type=importmap]")?.textContent || "{}")
    const links = [ ...document.querySelectorAll("link[rel=stylesheet], link[rel=icon], meta[name=qz-tray-src]") ].map((element) => element.href || element.content)
    return [ ...Object.values(importmap.imports || {}), ...links ].map((url) => new URL(url, location.href).pathname)
  }

  async update() {
    if (this.updating) return
    this.updating = true
    try {
      const online = navigator.onLine && await this.reachable()
      if (online) {
        await this.refreshCatalogue().catch(() => {})
        await this.sendWaiting().catch(() => {})
      }
      this.render(online, await store.sales.waiting())
    } finally {
      this.updating = false
    }
  }

  async reachable() {
    try {
      return (await fetch("/up", { cache: "no-store" })).ok
    } catch {
      return false
    }
  }

  async refreshCatalogue() {
    const current = await store.catalogue.get()
    if (current && current.till?.shift_id && Date.now() - current.fetched_at < this.constructor.CATALOGUE_MAX_AGE) return

    const headers = { Accept: "application/json" }
    if (current?.etag) headers["If-None-Match"] = current.etag
    const response = await fetch(this.catalogueUrlValue, { headers, redirect: "manual" })

    if (response.status === 304) {
      await store.catalogue.put({ ...current, fetched_at: Date.now() })
    } else if (response.ok && response.headers.get("Content-Type")?.includes("json")) {
      await store.catalogue.put({ ...(await response.json()), etag: response.headers.get("ETag"), fetched_at: Date.now() })
      this.dispatch("catalogue")
    }
  }

  async sendWaiting() {
    const waiting = await store.sales.waiting()
    if (waiting.length === 0) return

    const { token } = await (await fetch(this.tokenUrlValue, { headers: { Accept: "application/json" } })).json()
    const response = await fetch(this.salesUrlValue, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": token },
      body: JSON.stringify({ sales: waiting.map((sale) => sale.payload) })
    })
    if (!response.ok) return

    const { results } = await response.json()
    for (const result of results) {
      const sale = waiting.find((waitingSale) => waitingSale.uuid === result.uuid)
      if (!sale) continue

      if (result.status === "error") {
        Object.assign(sale, { status: "error", error: result.error })
      } else {
        Object.assign(sale, { status: "sent", result: result.status, receipt_number: result.receipt_number, sale_id: result.sale_id,
                              warnings: result.warnings, sent_at: new Date().toISOString() })
      }
      await store.sales.put(sale)
    }
    await this.forgetOldSales()
    this.dispatch("sent", { detail: { results } })
  }

  async forgetOldSales() {
    const sent = (await store.sales.all()).filter((sale) => sale.status === "sent").sort((a, b) => b.sent_at.localeCompare(a.sent_at))
    for (const sale of sent.slice(this.constructor.KEEP_SENT)) await store.sales.remove(sale.uuid)
  }

  render(online, waiting) {
    if (this.hasStatusTarget) {
      const count = waiting.length
      const pending = count ? ` · ${count} sale${count === 1 ? "" : "s"} ${online ? "sending" : "waiting"}` : ""
      this.statusTarget.textContent = (online ? "Online" : "Offline") + pending
      this.statusTarget.dataset.state = online ? "online" : "offline"
    }
    if (this.hasBannerTarget) {
      const show = this.offlinePageValue ? online && waiting.length === 0 : !online
      this.bannerTarget.hidden = !show
    }
  }
}
