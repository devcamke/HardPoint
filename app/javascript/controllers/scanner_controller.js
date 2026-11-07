import { Controller } from "@hotwired/stimulus"

// The till's scan box. A barcode scanner types the code and presses Enter, which submits the form
// and adds the product. Typing without Enter searches after a short pause.
//
// On a touch screen the box keeps focus for the scanner without opening the on-screen keyboard over
// the till; the keyboard comes up only when the cashier taps the box to search.
export default class extends Controller {
  static targets = [ "input" ]
  static values = { searchUrl: String }

  connect() {
    this.touch = window.matchMedia("(pointer: coarse)").matches
    if (this.touch) this.inputTarget.inputMode = "none"
  }

  allowKeyboard() {
    if (this.touch) this.inputTarget.inputMode = "search"
  }

  hideKeyboard() {
    if (this.touch) this.inputTarget.inputMode = "none"
  }

  search() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {
      const frame = document.getElementById("search_results")
      if (!frame) return
      const query = this.inputTarget.value.trim()
      if (query.length >= 2) frame.src = `${this.searchUrlValue}?query=${encodeURIComponent(query)}`
      else this.clearSearch(frame)
    }, 300)
  }

  reset(event) {
    clearTimeout(this.timeout)
    if (event.detail.success) this.clear()
    this.inputTarget.focus()
  }

  clear() {
    this.inputTarget.value = ""
    const frame = document.getElementById("search_results")
    if (frame) this.clearSearch(frame)
  }

  // Back to quick picks after a search; a category the cashier is browsing stays open.
  clearSearch(frame) {
    if (frame.src && new URL(frame.src, window.location.href).searchParams.has("query")) frame.src = this.searchUrlValue
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
