import { Controller } from "@hotwired/stimulus"

// Tapping a product tile at the till asks how many before adding it: the popup opens with 1 selected,
// so Enter (or "Add to sale") confirms and typing a number replaces it. − and + step it on a touch screen.
// Scanning still adds straight away; this is only for the tiles. Without JavaScript the tile adds one.
export default class extends Controller {
  static targets = [ "dialog", "form", "name", "price", "unit", "productId", "productUnitId", "quantity" ]

  ask(event) {
    const tile = event.currentTarget
    event.preventDefault()

    this.nameTarget.textContent = tile.dataset.name
    this.priceTarget.textContent = tile.dataset.price
    this.unitTarget.textContent = tile.dataset.unit
    this.productIdTarget.value = tile.dataset.productId
    this.productUnitIdTarget.value = tile.dataset.productUnitId || ""
    this.fractional = tile.dataset.fractional === "true"
    this.quantityTarget.step = this.fractional ? "any" : "1"
    this.quantityTarget.min = this.fractional ? "0.001" : "1"
    this.quantityTarget.value = "1"

    this.dialogTarget.showModal()
    this.quantityTarget.focus()
    this.quantityTarget.select()
  }

  less() { this.step(-1) }
  more() { this.step(1) }

  step(by) {
    const current = parseFloat(this.quantityTarget.value) || 0
    const next = Math.max(1, Math.round((current + by) * 1000) / 1000)
    this.quantityTarget.value = String(next)
    this.quantityTarget.focus()
  }

  // Turbo answers with the cart; close and hand focus back to the scan box for the next item.
  submitted(event) {
    if (!event.detail.success) return
    this.close()
    document.querySelector("[data-scanner-target='input']")?.focus()
  }

  close() {
    if (this.dialogTarget.open) this.dialogTarget.close()
  }

  closeOnBackdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }
}
