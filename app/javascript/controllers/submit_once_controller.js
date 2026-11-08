import { Controller } from "@hotwired/stimulus"

// For forms that leave Turbo out (uploads, sign-up, card checkout): Turbo isn't there to disable the button, so a double
// click would send the form twice. The button comes back if the browser restores the page from its back/forward cache.
export default class extends Controller {
  connect() {
    this.restore = (event) => { if (event.persisted) this.enable() }
    window.addEventListener("pageshow", this.restore)
  }

  disconnect() {
    window.removeEventListener("pageshow", this.restore)
  }

  submit(event) {
    if (this.element.dataset.submitting) return event.preventDefault()
    this.element.dataset.submitting = "true"
    // After the browser has gathered the form's fields, so the pressed button's own value is still sent.
    setTimeout(() => this.buttons.forEach((button) => { button.disabled = true }))
  }

  enable() {
    delete this.element.dataset.submitting
    this.buttons.forEach((button) => { button.disabled = false })
  }

  get buttons() {
    return this.element.querySelectorAll("button[type=submit], button:not([type]), input[type=submit]")
  }
}
