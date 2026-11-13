import { Controller } from "@hotwired/stimulus"

// The landing page's "Getting started" path (pages/home): five steps as tabs on a progress line, each showing its
// screen in a browser frame. It plays through on its own until the visitor touches it, pauses while the pointer or
// focus is on it, and sits still for anyone who prefers reduced motion. Without JavaScript the five steps are
// simply listed, with the first screen showing.
export default class extends Controller {
  static targets = [ "tab", "panel", "screen", "fill", "previous", "next", "count" ]
  static values = { index: { type: Number, default: 0 }, interval: { type: Number, default: 5000 } }

  connect() {
    this.element.classList.add("is-interactive")
    this.show(0)
    if (!matchMedia("(prefers-reduced-motion: reduce)").matches) this.play()
  }

  disconnect() {
    this.stop()
  }

  select(event) {
    this.stop()
    this.show(Number(event.currentTarget.dataset.index))
  }

  previous() {
    this.stop()
    this.show(this.indexValue - 1)
  }

  next() {
    this.stop()
    this.show(this.indexValue + 1)
  }

  keydown(event) {
    if (event.key === "ArrowRight") { event.preventDefault(); this.next() }
    if (event.key === "ArrowLeft") { event.preventDefault(); this.previous() }
  }

  // Hovering or tabbing into the path holds the current step; leaving lets it carry on if it was playing.
  pause() {
    clearTimeout(this.timer)
    this.timer = null
  }

  resume() {
    if (this.playing) this.play()
  }

  play() {
    this.playing = true
    this.element.classList.add("is-playing")
    clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      this.show((this.indexValue + 1) % this.tabTargets.length)
      this.play()
    }, this.intervalValue)
  }

  stop() {
    this.playing = false
    this.element.classList.remove("is-playing")
    clearTimeout(this.timer)
    this.timer = null
  }

  show(index) {
    const last = this.tabTargets.length - 1
    index = Math.max(0, Math.min(last, index))
    this.indexValue = index
    this.tabTargets.forEach((tab, i) => {
      tab.setAttribute("aria-selected", i === index)
      tab.tabIndex = i === index ? 0 : -1
      tab.classList.toggle("is-active", i === index)
      tab.classList.toggle("is-done", i < index)
    })
    this.panelTargets.forEach((panel, i) => { panel.hidden = i !== index })
    this.screenTargets.forEach((screen, i) => screen.classList.toggle("is-active", i === index))
    this.fillTarget.style.width = `${(index / last) * 80}%`
    this.previousTarget.disabled = index === 0
    this.nextTarget.disabled = index === last
    this.countTarget.textContent = `Step ${index + 1} of ${this.tabTargets.length}`
  }
}
