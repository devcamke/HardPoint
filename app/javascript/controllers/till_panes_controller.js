import { Controller } from "@hotwired/stimulus"

// On a phone the till shows one pane at a time: the products to tap, or the sale and payment.
// Wider screens show both side by side and never see the tabs.
export default class extends Controller {
  show(event) {
    this.element.dataset.pane = event.currentTarget.dataset.pane
  }
}
