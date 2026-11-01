import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// The search bar of a list page, as in Odoo: Enter turns the typed text into a "Search" facet, Backspace in an
// empty box removes the last facet, and the arrow opens the filters.
export default class extends Controller {
  static targets = [ "input", "query", "facetRemover", "toggle", "dropdown" ]

  submit(event) {
    if (!this.hasInputTarget) return

    const text = this.inputTarget.value.trim()
    if (text === "" && !this.filterChanged) {
      event.preventDefault()
      return
    }
    if (this.hasQueryTarget) {
      if (text !== "") this.queryTarget.value = text
      this.queryTarget.disabled = this.queryTarget.value === ""
    }
  }

  keydown(event) {
    if (event.key === "Backspace" && this.inputTarget.value === "" && this.hasFacetRemoverTarget) {
      event.preventDefault()
      Turbo.visit(this.facetRemoverTargets[this.facetRemoverTargets.length - 1].href)
    }
  }

  submitFilters() {
    this.filterChanged = true
    this.element.requestSubmit()
  }

  toggle() {
    this.dropdownTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.dropdownTarget.hidden = false
    this.toggleTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    if (!this.hasDropdownTarget || this.dropdownTarget.hidden) return
    this.dropdownTarget.hidden = true
    this.toggleTarget.setAttribute("aria-expanded", "false")
  }

  closeOnOutsideClick(event) {
    if (!this.element.contains(event.target)) this.close()
  }
}
