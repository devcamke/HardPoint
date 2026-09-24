import { Controller } from "@hotwired/stimulus"

// Hides a banner once dismissed, remembered in this browser (e.g. a platform announcement).
export default class extends Controller {
  static values = { key: String }

  connect() {
    if (this.#dismissed()) this.element.hidden = true
  }

  dismiss() {
    this.element.hidden = true
    try { localStorage.setItem(this.#storageKey, "1") } catch {}
  }

  #dismissed() {
    try { return localStorage.getItem(this.#storageKey) === "1" } catch { return false }
  }

  get #storageKey() {
    return `dismissed:${this.keyValue}`
  }
}
