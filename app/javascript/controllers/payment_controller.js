import { Controller } from "@hotwired/stimulus"

// Shows the right fields for the chosen tender and the change due as cash is typed. On a touch screen the
// number pad types the amount, and the amount boxes don't open the device's own keyboard over the till.
export default class extends Controller {
  static targets = [ "cashFields", "otherFields", "referenceField", "approvalField", "mpesaFields", "airtelFields", "quickCash", "tendered", "amount", "change",
                     "foreignFields", "currency", "foreignTendered", "keypad", "keypadToggle", "exactKey" ]
  static values = { due: Number }

  connect() {
    this.touch = window.matchMedia("(pointer: coarse)").matches
    if (this.touch) {
      [ this.tenderedTarget, this.amountTarget, this.hasForeignTenderedTarget && this.foreignTenderedTarget ]
        .filter(Boolean).forEach((input) => (input.inputMode = "none"))
      // Left as the cashier last had it; at first, open only where the screen is tall enough to keep the cart in view.
      const saved = this.storedKeypad
      this.showKeypad(saved === null ? window.innerHeight >= 900 : saved === "open")
    }
    this.switchTender()
  }

  openKeypad() {
    if (this.touch) this.showKeypad(true, true)
  }

  toggleKeypad() {
    this.showKeypad(this.keypadTarget.classList.contains("hidden"), true)
  }

  showKeypad(open, remember = false) {
    this.keypadTarget.classList.toggle("hidden", !open)
    this.keypadTarget.classList.toggle("grid", open)
    this.keypadToggleTarget.setAttribute("aria-expanded", open)
    if (remember) this.storedKeypad = open ? "open" : "closed"
    // Opened by the cashier on a short screen: bring the pad and "Take payment" into view.
    if (open && remember) requestAnimationFrame(() => this.element.scrollIntoView({ block: "end", behavior: "smooth" }))
  }

  get storedKeypad() {
    try { return window.localStorage.getItem("hardpoint.keypad") } catch { return null }
  }

  set storedKeypad(value) {
    try { window.localStorage.setItem("hardpoint.keypad", value) } catch { /* private mode: not remembered */ }
  }

  switchTender() {
    const tender = this.element.querySelector("input[name=tender]:checked")?.value || "cash"
    const cash = tender === "cash"
    const foreign = tender === "foreign_cash"
    this.cashFieldsTarget.classList.toggle("hidden", !cash)
    this.quickCashTarget.classList.toggle("hidden", !cash)
    this.otherFieldsTarget.classList.toggle("hidden", cash || foreign)
    if (this.hasForeignFieldsTarget) this.foreignFieldsTarget.classList.toggle("hidden", !foreign)
    this.referenceFieldTarget.classList.toggle("hidden", !(tender === "mobile_money" || tender === "airtel_money" || tender === "card"))
    if (this.hasMpesaFieldsTarget) this.mpesaFieldsTarget.classList.toggle("hidden", tender !== "mobile_money")
    if (this.hasAirtelFieldsTarget) this.airtelFieldsTarget.classList.toggle("hidden", tender !== "airtel_money")
    if (this.hasApprovalFieldTarget) this.approvalFieldTarget.classList.toggle("hidden", tender !== "on_account")
    // A deposit can only cover what's held; otherwise the amount defaults to what's due.
    const deposit = this.amountTarget.dataset.deposit
    if (deposit) this.amountTarget.value = tender === "deposit" ? deposit : (this.dueValue / 100).toFixed(2)
    if (this.hasExactKeyTarget) this.exactKeyTarget.classList.toggle("invisible", foreign)
    this.replaceOnPress = true
    this.showChange()
  }

  fill(event) {
    this.tenderedTarget.value = event.currentTarget.dataset.amount
    this.replaceOnPress = true
    this.showChange()
    this.tenderedTarget.focus()
  }

  // The number pad. The first digit replaces a filled-in amount (what's due, or a quick-cash note).
  press(event) {
    const key = event.currentTarget.dataset.key
    const input = this.keypadInput
    let value = this.replaceOnPress || input.value !== this.keypadShown ? input.value : this.keypadValue
    if (this.replaceOnPress && /^[0-9.]/.test(key)) value = ""
    this.replaceOnPress = false

    if (key === "back") value = value.slice(0, -1)
    else if (key === "clear") value = ""
    else if (key === "exact") { value = (this.dueValue / 100).toFixed(2); this.replaceOnPress = true }
    else if (key === ".") { if (!value.includes(".")) value = `${value || "0"}.` }
    else {
      const typed = `${value}${key}`.replace(/^0+(?=\d)/, "")
      if (!/\.\d{3,}$/.test(typed)) value = typed
    }

    // A number box can't hold "12." while the cashier types the cents, so the pad keeps what was typed.
    this.keypadValue = value
    this.keypadShown = input.value = value.endsWith(".") ? value.slice(0, -1) : value
    this.showChange()
  }

  get keypadInput() {
    if (!this.cashFieldsTarget.classList.contains("hidden")) return this.tenderedTarget
    if (this.hasForeignFieldsTarget && !this.foreignFieldsTarget.classList.contains("hidden")) return this.foreignTenderedTarget
    return this.amountTarget
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
