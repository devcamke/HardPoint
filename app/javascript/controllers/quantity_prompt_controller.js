import { Controller } from "@hotwired/stimulus"

// Tapping a product tile at the till asks how many before adding it: the popup opens with 1 selected,
// so Enter (or "Add to sale") confirms and typing a number replaces it. − and + step it on a touch screen.
// Scanning still adds straight away; this is only for the tiles. Without JavaScript the tile adds one.
// A product cut to length is asked for as pieces × length each, and one sold by the kilogram can be weighed on the
// till's scale (scale_controller).
export default class extends Controller {
  static targets = [ "dialog", "form", "name", "price", "unit", "productId", "productUnitId", "quantity", "plain", "cut", "pieces", "cutLength", "cutUnit", "rack", "weigh" ]

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

    // A product cut to length asks for pieces and the length of each instead; one sold by weight can be weighed.
    const cut = Boolean(tile.dataset.stockLength)
    this.cutTarget.hidden = !cut
    this.plainTarget.hidden = cut
    this.quantityTarget.disabled = cut
    this.piecesTarget.disabled = this.cutLengthTarget.disabled = !cut
    if (cut) {
      this.piecesTarget.value = "1"
      this.cutLengthTarget.value = ""
      this.cutLengthTarget.max = tile.dataset.stockLength
      this.cutUnitTarget.textContent = tile.dataset.unit
      this.rackTarget.textContent = `Comes in ${tile.dataset.stockLength} ${tile.dataset.unit} lengths. Here: ${tile.dataset.rack || "none"}`
    }
    if (this.hasWeighTarget) {
      this.weighTarget.hidden = !tile.dataset.perKilogram
      this.plainTarget.dataset.scalePerKilogramValue = tile.dataset.perKilogram || "1"
    }

    this.dialogTarget.showModal()
    const first = cut ? this.cutLengthTarget : this.quantityTarget
    first.focus()
    first.select()
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
