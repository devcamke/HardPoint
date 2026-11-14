import { Controller } from "@hotwired/stimulus"
import { readScale } from "scale/reader"
import { inUnit } from "scale/weight"

// "Weigh" at the till: reads the scale on this till's serial port and puts the weight in the quantity box, in the
// product's own unit (kilograms or grams). The till's scale settings come from Settings › Tills.
export default class extends Controller {
  static targets = [ "input", "status", "button" ]
  static values = { mode: String, baudRate: Number, framing: String, perKilogram: { type: Number, default: 1 } }

  async read(event) {
    event.preventDefault()
    const perKilogram = Number(event.params.perKilogram) || this.perKilogramValue
    this.buttonTargets.forEach((button) => button.disabled = true)
    this.say("Reading the scale…")

    try {
      const kilograms = await readScale({ mode: this.modeValue, baudRate: this.baudRateValue, framing: this.framingValue })
      this.inputTarget.value = String(inUnit(kilograms, perKilogram))
      this.say("")
      this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
    } catch (error) {
      // Closing the browser's port chooser without picking one isn't worth a message.
      this.say(error.name === "NotFoundError" ? "" : error.message)
    } finally {
      this.buttonTargets.forEach((button) => button.disabled = false)
    }
  }

  say(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
