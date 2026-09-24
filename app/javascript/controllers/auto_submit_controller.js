import { Controller } from "@hotwired/stimulus"

// Submits its form when a field changes, or after a pause in typing for search boxes.
export default class extends Controller {
  static values = { delay: { type: Number, default: 250 } }

  submit() {
    clearTimeout(this.timeout)
    this.element.requestSubmit()
  }

  debouncedSubmit() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.element.requestSubmit(), this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
