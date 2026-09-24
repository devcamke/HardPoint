import { Controller } from "@hotwired/stimulus"

// Shows the right fields for the chosen tender and the change due as cash is typed.
export default class extends Controller {
  static targets = [ "cashFields", "otherFields", "referenceField", "approvalField", "mpesaFields", "quickCash", "tendered", "amount", "change" ]
  static values = { due: Number }

  connect() {
    this.switchTender()
  }

  switchTender() {
    const tender = this.element.querySelector("input[name=tender]:checked")?.value || "cash"
    const cash = tender === "cash"
    this.cashFieldsTarget.classList.toggle("hidden", !cash)
    this.quickCashTarget.classList.toggle("hidden", !cash)
    this.otherFieldsTarget.classList.toggle("hidden", cash)
    this.referenceFieldTarget.classList.toggle("hidden", !(tender === "mobile_money" || tender === "card"))
    if (this.hasMpesaFieldsTarget) this.mpesaFieldsTarget.classList.toggle("hidden", tender !== "mobile_money")
    if (this.hasApprovalFieldTarget) this.approvalFieldTarget.classList.toggle("hidden", tender !== "on_account")
    // A deposit can only cover what's held; otherwise the amount defaults to what's due.
    const deposit = this.amountTarget.dataset.deposit
    if (deposit) this.amountTarget.value = tender === "deposit" ? deposit : (this.dueValue / 100).toFixed(2)
    this.showChange()
  }

  fill(event) {
    this.tenderedTarget.value = event.currentTarget.dataset.amount
    this.showChange()
    this.tenderedTarget.focus()
  }

  showChange() {
    const tendered = Math.round(parseFloat(this.tenderedTarget.value || "0") * 100)
    const change = tendered - this.dueValue
    const cash = !this.cashFieldsTarget.classList.contains("hidden")
    this.changeTarget.textContent = cash && tendered > 0 && change >= 0 ? `Change: ${(change / 100).toLocaleString(undefined, { minimumFractionDigits: 2 })}` : ""
  }

  reset() {
    const scanner = document.querySelector("[data-shortcuts-target=scanner]")
    if (scanner) scanner.focus()
  }
}
