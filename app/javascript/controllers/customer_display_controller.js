import { Controller } from "@hotwired/stimulus"

// The customer-facing screen: shows what the till beside it is ringing up. The till and this page
// run in the same browser (a second monitor, or a second window), so they talk directly and it
// keeps working offline.
export default class extends Controller {
  static targets = [ "lines", "total", "label", "note" ]
  static values = { shop: String }

  connect() {
    this.channel = new BroadcastChannel("hardpoint-display")
    this.channel.onmessage = ({ data }) => this.show(data)
    this.show({ status: "idle" })
  }

  disconnect() {
    this.channel.close()
  }

  show({ status, lines = [], total = "", change, paybill }) {
    if (status === "complete") {
      this.linesTarget.innerHTML = `<li class="py-12 text-center text-5xl font-bold">Thank you!</li>`
      this.labelTarget.textContent = "Paid"
      this.totalTarget.textContent = total
      this.noteTarget.textContent = change ? `Your change: ${change}` : ""
    } else if (status === "cart" && lines.length) {
      this.linesTarget.innerHTML = lines.map((line) => `<li class="flex justify-between gap-6 py-3"><span>${escape(line.description)}
        <span class="block text-lg text-navy-300">× ${escape(line.quantity)}</span></span><span class="tabular-nums">${escape(line.total)}</span></li>`).join("")
      this.labelTarget.textContent = "Total"
      this.totalTarget.textContent = total
      this.noteTarget.textContent = paybill ? `Pay with M-Pesa: ${paybill}` : ""
      this.linesTarget.lastElementChild?.scrollIntoView({ block: "end" })
    } else {
      this.linesTarget.innerHTML = `<li class="py-12 text-center text-4xl font-semibold">Welcome to ${escape(this.shopValue)}</li>`
      this.labelTarget.textContent = ""
      this.totalTarget.textContent = ""
      this.noteTarget.textContent = ""
    }
  }
}

function escape(value) {
  return String(value ?? "").replace(/[&<>"']/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[character])
}
