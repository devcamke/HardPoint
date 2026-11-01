import { Controller } from "@hotwired/stimulus"

// A menu under a button: opens and closes on click, closes on Escape or a click elsewhere.
export default class extends Controller {
  static targets = [ "toggle", "menu" ]

  toggle() {
    this.menuTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.menuTarget.hidden = false
    this.toggleTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    if (!this.hasMenuTarget || this.menuTarget.hidden) return
    this.menuTarget.hidden = true
    this.toggleTarget.setAttribute("aria-expanded", "false")
  }

  closeOnOutsideClick(event) {
    if (!this.element.contains(event.target)) this.close()
  }
}
