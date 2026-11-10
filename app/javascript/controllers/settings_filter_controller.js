import { Controller } from "@hotwired/stimulus"

// Narrows the Settings page to the cards whose name, description or keywords match what's typed, hiding groups left empty.
export default class extends Controller {
  static targets = [ "query", "card", "section", "empty" ]

  filter() {
    const words = this.queryTarget.value.toLowerCase().trim().split(/\s+/).filter(Boolean)
    this.cardTargets.forEach((card) => {
      const text = card.dataset.search
      card.hidden = !words.every((word) => text.includes(word))
    })
    this.sectionTargets.forEach((section) => {
      section.hidden = section.querySelectorAll("[data-settings-filter-target=card]:not([hidden])").length === 0
    })
    this.emptyTarget.hidden = this.cardTargets.some((card) => !card.hidden)
  }

  // Enter opens the only card left, Escape clears the search.
  keydown(event) {
    if (event.key === "Escape") {
      this.queryTarget.value = ""
      this.filter()
    } else if (event.key === "Enter") {
      const visible = this.cardTargets.filter((card) => !card.hidden)
      if (visible.length === 1) visible[0].click()
    }
  }
}
