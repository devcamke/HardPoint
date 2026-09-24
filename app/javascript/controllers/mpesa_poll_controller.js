import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// While a customer is answering an M-Pesa prompt, asks the server every few seconds whether they
// have, then reloads the till (or shows the finished sale).
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.timer = setInterval(() => this.check(), 2500)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async check() {
    const response = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
    if (!response.ok) return

    const { status, location } = await response.json()
    if (status !== "pending") {
      clearInterval(this.timer)
      Turbo.visit(location)
    }
  }
}
