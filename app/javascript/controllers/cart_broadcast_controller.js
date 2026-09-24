import { Controller } from "@hotwired/stimulus"

// Tells the customer display (in another window of this browser) what's in the cart each time
// the cart is drawn, and when a sale completes.
export default class extends Controller {
  static values = { state: Object }

  connect() {
    if (!("BroadcastChannel" in window)) return
    const channel = new BroadcastChannel("hardpoint-display")
    channel.postMessage(this.stateValue)
    channel.close()
  }
}
