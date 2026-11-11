import { Controller } from "@hotwired/stimulus"

// The landing page's example till: "Pull the plug on the internet" shows what changes when the till is offline.
// Each text target carries its offline wording in data-offline-text; the online wording is whatever it shows on load.
// The button is hidden in the HTML and only appears once this has connected, so it never does nothing.
export default class extends Controller {
  static targets = [ "till", "text", "button" ]

  connect() {
    this.offline = false
    this.textTargets.forEach(target => target.dataset.onlineText = target.textContent)
    this.buttonTarget.hidden = false
  }

  toggle() {
    this.offline = !this.offline
    this.tillTarget.classList.toggle("is-offline", this.offline)
    this.buttonTarget.setAttribute("aria-pressed", String(this.offline))
    this.textTargets.forEach(target => {
      target.textContent = this.offline ? target.dataset.offlineText : target.dataset.onlineText
    })
  }
}
