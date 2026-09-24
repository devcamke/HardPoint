import { Controller } from "@hotwired/stimulus"

// Selects a read-only field's text when it's focused, ready to copy.
export default class extends Controller {
  connect() {
    this.element.addEventListener("focus", () => this.element.select())
  }
}
