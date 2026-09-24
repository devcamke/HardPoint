import { Controller } from "@hotwired/stimulus"

// Typing dates switches the period from a preset ("This month") to those dates.
export default class extends Controller {
  static targets = [ "preset" ]

  chooseDates() {
    if (this.hasPresetTarget) this.presetTarget.value = ""
  }
}
