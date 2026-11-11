import { Controller } from "@hotwired/stimulus"

// Copies a value (a link to send) to the clipboard, and says so on the button for a moment.
export default class extends Controller {
  static targets = [ "source", "button" ]

  async copy() {
    const value = this.sourceTarget.value || this.sourceTarget.textContent
    try {
      await navigator.clipboard.writeText(value.trim())
    } catch {
      this.sourceTarget.select?.()
      return
    }
    const label = this.buttonTarget.textContent
    this.buttonTarget.textContent = "Copied"
    setTimeout(() => { this.buttonTarget.textContent = label }, 1500)
  }
}
