import { Controller } from "@hotwired/stimulus"

// Keyboard shortcuts at the till: F2 scan, F8 park, F9 pay.
export default class extends Controller {
  handle(event) {
    switch (event.key) {
      case "F2":
        event.preventDefault()
        this.focus("scanner")
        break
      case "F8": {
        event.preventDefault()
        const form = document.querySelector("[data-shortcuts-target=park]")
        if (form) form.requestSubmit()
        break
      }
      case "F9":
        event.preventDefault()
        this.focus("pay")
        break
    }
  }

  focus(name) {
    const element = document.querySelector(`[data-shortcuts-target=${name}]`)
    if (element) { element.focus(); element.select?.() }
  }
}
