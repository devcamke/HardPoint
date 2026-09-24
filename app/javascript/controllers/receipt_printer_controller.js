import { Controller } from "@hotwired/stimulus"
import { printReceipt, openDrawer } from "offline/printer"

// On a till set to print through QZ Tray: receipts go straight to the receipt printer (which
// opens the drawer for cash sales), and the drawer can be opened without a sale. Other tills
// keep using the browser's receipt page.
export default class extends Controller {
  static values = { till: Object, receiptUrl: String, drawerUrl: String, auto: Boolean }

  connect() {
    if (this.autoValue && this.direct) this.print()
  }

  get direct() {
    return this.tillValue.print_mode === "qz_tray"
  }

  async print(event) {
    if (!this.direct) return
    event?.preventDefault()
    try {
      const response = await fetch(this.receiptUrlValue, { headers: { Accept: "application/json" } })
      await printReceipt(await response.json(), this.tillValue)
    } catch (error) {
      alert(`The receipt printer didn't answer (${error.message}). Opening the receipt to print through the browser.`)
      window.open(this.receiptUrlValue.replace(/\.json$/, "?print=1"), "_blank")
    }
  }

  async openDrawer() {
    try {
      await openDrawer(this.tillValue.printer_name)
      await fetch(this.drawerUrlValue, { method: "POST", headers: { "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content } })
    } catch (error) {
      alert(`The cash drawer didn't open (${error.message}). Is QZ Tray running?`)
    }
  }
}
