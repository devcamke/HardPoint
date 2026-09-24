import { Controller } from "@hotwired/stimulus"

// The till's scan box. A barcode scanner types the code and presses Enter, which submits the form
// and adds the product. Typing without Enter searches after a short pause.
export default class extends Controller {
  static targets = [ "input" ]
  static values = { searchUrl: String }

  search() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {
      const frame = document.getElementById("search_results")
      if (!frame) return
      const query = this.inputTarget.value.trim()
      frame.src = query.length >= 2 ? `${this.searchUrlValue}?query=${encodeURIComponent(query)}` : this.searchUrlValue
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
    if (frame && frame.src !== this.searchUrlValue) frame.src = this.searchUrlValue
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
