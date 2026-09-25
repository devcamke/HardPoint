import { Controller } from "@hotwired/stimulus"

// Shows the right fields for the chosen tender and the change due as cash is typed.
export default class extends Controller {
  static targets = [ "cashFields", "otherFields", "referenceField", "approvalField", "mpesaFields", "quickCash", "tendered", "amount", "change",
                     "foreignFields", "currency", "foreignTendered" ]
  static values = { due: Number }

  connect() {
    this.switchTender()
  }

  switchTender() {
    const tender = this.element.querySelector("input[name=tender]:checked")?.value || "cash"
    const cash = tender === "cash"
    const foreign = tender === "foreign_cash"
    this.cashFieldsTarget.classList.toggle("hidden", !cash)
    this.quickCashTarget.classList.toggle("hidden", !cash)
    this.otherFieldsTarget.classList.toggle("hidden", cash || foreign)
    if (this.hasForeignFieldsTarget) this.foreignFieldsTarget.classList.toggle("hidden", !foreign)
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
    if (this.hasForeignFieldsTarget && !this.foreignFieldsTarget.classList.contains("hidden")) return this.showForeignChange()

    const tendered = Math.round(parseFloat(this.tenderedTarget.value || "0") * 100)
    const change = tendered - this.dueValue
    const cash = !this.cashFieldsTarget.classList.contains("hidden")
    this.changeTarget.textContent = cash && tendered > 0 && change >= 0 ? `Change: ${(change / 100).toLocaleString(undefined, { minimumFractionDigits: 2 })}` : ""
  }

  // Foreign notes: what they're worth here at the shop's rate (rounded down, as the server does) and the change.
  showForeignChange() {
    const option = this.currencyTarget.selectedOptions[0]
    const foreignCents = Math.round(parseFloat(this.foreignTenderedTarget.value || "0") * 100)
    if (!option || foreignCents <= 0) return this.changeTarget.textContent = `1 ${option?.value} = ${parseFloat(option?.dataset.rate || 0)}`

    const worth = Math.floor(foreignCents * parseFloat(option.dataset.rate))
    const format = (cents) => (cents / 100).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
    const change = worth - this.dueValue
    this.changeTarget.textContent = change >= 0 ? `Worth ${format(worth)}. Change: ${format(change)}` : `Worth ${format(worth)}. ${format(-change)} still due`
  }

  reset() {
    const scanner = document.querySelector("[data-shortcuts-target=scanner]")
    if (scanner) scanner.focus()
  }
}
