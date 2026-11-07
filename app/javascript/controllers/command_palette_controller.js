import { Controller } from "@hotwired/stimulus"

// The search popup in the top bar: Ctrl K (⌘K on a Mac) or a click opens it, typing searches as you go,
// ↑ ↓ pick a result and Enter opens it. A barcode scanned into it opens the product, since a scanner
// types the code and presses Enter.
export default class extends Controller {
  static targets = [ "dialog", "form", "input", "result" ]

  connect() {
    this.selected = -1
  }

  shortcut(event) {
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") {
      event.preventDefault()
      this.open()
    }
  }

  open() {
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
    this.inputTarget.focus()
    this.inputTarget.select()
  }

  close() {
    this.dialogTarget.close()
  }

  // The owner's dashboard redraws itself (a Turbo morph) whenever a sale comes in. Left alone, that
  // closes this popup and wipes what's being typed, so while it's open the redraw passes it by.
  keepWhileOpen(event) {
    if (this.dialogTarget.open) event.preventDefault()
  }

  closeOnBackdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  search() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.formTarget.requestSubmit(), 150)
  }

  resultTargetConnected() {
    this.select(0)
  }

  navigate(event) {
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.select(this.selected + 1)
        break
      case "ArrowUp":
        event.preventDefault()
        this.select(this.selected - 1)
        break
      // A search box takes Esc to clear itself, so the popup wouldn't close on it otherwise.
      case "Escape":
        event.preventDefault()
        this.close()
        break
      case "Enter": {
        event.preventDefault()
        clearTimeout(this.timer)
        const result = this.resultTargets[this.selected]
        if (result && !this.pending) {
          result.click()
        } else {
          window.location.assign(`${this.formTarget.action}?q=${encodeURIComponent(this.inputTarget.value)}`)
        }
        break
      }
    }
  }

  // While a search is on its way, Enter waits for the answer rather than opening a stale result.
  submitStart() { this.pending = true }
  submitEnd() { this.pending = false }

  select(index) {
    const results = this.resultTargets
    if (results.length === 0) return (this.selected = -1)

    this.selected = (index + results.length) % results.length
    results.forEach((result, i) => result.setAttribute("aria-selected", i === this.selected))
    results[this.selected].scrollIntoView({ block: "nearest" })
  }
}
