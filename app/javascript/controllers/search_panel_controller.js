import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// The search bar of a list page. What's typed is searched as it's typed: a moment after the typing stops, the list
// reloads with the results, and the box carries on where it was (focus, text and caret), including anything typed
// while the results were on their way, which is then searched too. Enter searches at once, as a barcode scanner
// does. Filters show as facets: Backspace in an empty box removes the last one, and the arrow opens the filters.
const DELAY = 300
const STORAGE_KEY = "search-panel:typing"
const CARRY_FOR = 10_000 // a reload that takes longer than this is someone else's visit, not this search's

export default class extends Controller {
  static targets = [ "input", "facetRemover", "toggle", "dropdown" ]

  connect() {
    if (!this.hasInputTarget) return

    this.searched = this.inputTarget.value.trim()
    const carried = this.carried()
    if (carried) {
      this.inputTarget.focus()
      if (carried.value !== this.inputTarget.value) {
        this.inputTarget.value = carried.value
        this.schedule()
      }
      const end = this.inputTarget.value.length
      this.inputTarget.setSelectionRange(end, end)
    }
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  type() {
    this.remember()
    this.schedule()
  }

  schedule() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.search(), DELAY)
  }

  // One letter matches too much to be worth a reload; an empty box shows everything again.
  search() {
    const text = this.inputTarget.value.trim()
    if (text === this.searched || text.length === 1) return

    this.searched = text
    this.remember()
    this.element.dataset.turboAction = "replace" // typing isn't a page to go back to
    this.element.requestSubmit()
    delete this.element.dataset.turboAction
  }

  submit(event) {
    clearTimeout(this.timeout)
    if (!this.hasInputTarget) return

    const text = this.inputTarget.value.trim()
    const searching = new URL(location.href).searchParams.get(this.inputTarget.name)
    if (text === "" && !searching && !this.filterChanged) {
      event.preventDefault()
      return
    }
    this.inputTarget.value = text
    this.inputTarget.disabled = text === "" // no empty "query=" in the address
    if (document.activeElement === this.inputTarget || this.inputTarget.disabled) this.remember()
    // The form's fields are read as the submit is handled; enabled again after, so a page Back to it isn't disabled.
    setTimeout(() => { this.inputTarget.disabled = false })
  }

  keydown(event) {
    if (event.key === "Backspace" && this.inputTarget.value === "" && this.hasFacetRemoverTarget) {
      event.preventDefault()
      this.forget()
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

  // What's in the box, kept for the page the search loads (this tab only, and only for a few seconds).
  remember() {
    try {
      sessionStorage.setItem(STORAGE_KEY, JSON.stringify({ path: location.pathname, value: this.inputTarget.value, at: Date.now() }))
    } catch {}
  }

  forget() {
    try { sessionStorage.removeItem(STORAGE_KEY) } catch {}
  }

  carried() {
    try {
      const saved = JSON.parse(sessionStorage.getItem(STORAGE_KEY) || "null")
      this.forget()
      if (saved && saved.path === location.pathname && Date.now() - saved.at < CARRY_FOR) return saved
    } catch {}
    return null
  }
}
