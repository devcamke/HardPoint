import { Controller } from "@hotwired/stimulus"

// A modal <dialog> opened by a button elsewhere on the page (the landing page's "Watch a sale"). Escape closes it
// natively; so does a click on the backdrop or on anything with data-action="dialog#close".
export default class extends Controller {
  static targets = [ "dialog" ]

  open(event) {
    event?.preventDefault()
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  closeOnBackdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }
}
