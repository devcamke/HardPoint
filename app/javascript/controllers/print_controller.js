import { Controller } from "@hotwired/stimulus"

// A "Print" button (no inline onclick, which the content security policy blocks).
export default class extends Controller {
  print() {
    window.print()
  }
}
