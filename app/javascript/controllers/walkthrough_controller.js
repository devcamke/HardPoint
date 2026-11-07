import { Controller } from "@hotwired/stimulus"

// A walkthrough of a screenshot in a help guide (help/_walkthrough): numbered hotspots on the screen, a spotlight on
// the current one, and a pop-up whose arrow points at it. Each hotspot carries its target's box on the screenshot,
// as percentages: data-box="x,y,width,height".
export default class extends Controller {
  static targets = [ "stage", "spotlight", "hotspot", "start", "popover", "arrow", "popoverStep", "popoverTitle", "popoverText",
    "popoverPrevious", "popoverNext", "dot", "item", "controls", "count", "previous", "next" ]

  static GAP = 14        // between the target and the pop-up, room for the arrow
  static MARGIN = 8      // keeps the pop-up off the screenshot's edges
  static DOCK_BELOW = 560 // narrower than this, the pop-up sits under the screenshot

  connect() {
    this.index = null
    this.element.classList.add("is-interactive")
    this.startTarget.hidden = false
    this.controlsTarget.hidden = false
    this.updateCount()
    this.resizeObserver = new ResizeObserver(() => this.place())
    this.resizeObserver.observe(this.stageTarget)
  }

  disconnect() {
    this.resizeObserver?.disconnect()
  }

  begin() {
    this.go(0)
  }

  show(event) {
    this.go(Number(event.currentTarget.dataset.index))
  }

  next() {
    if (this.index === null) this.go(0)
    else if (this.index < this.count - 1) this.go(this.index + 1)
    else this.finish()
  }

  previous() {
    if (this.index > 0) this.go(this.index - 1)
  }

  keydown(event) {
    if (event.key === "ArrowRight") { event.preventDefault(); this.next() }
    else if (event.key === "ArrowLeft") { event.preventDefault(); this.previous() }
    else if (event.key === "Escape" && this.index !== null) { event.preventDefault(); this.finish() }
  }

  go(index) {
    this.index = index
    const hotspot = this.hotspotTargets[index]
    const item = this.itemTargets[index]

    this.element.classList.add("is-touring")
    this.startTarget.hidden = true
    this.hotspotTargets.forEach((each, i) => each.classList.toggle("is-active", i === index))
    this.itemTargets.forEach((each, i) => each.classList.toggle("is-active", i === index))
    this.dotTargets.forEach((each, i) => each.classList.toggle("is-active", i === index))

    this.popoverStepTarget.textContent = `Step ${index + 1} of ${this.count}`
    this.popoverTitleTarget.textContent = item.querySelector("strong").textContent.replace(/\.$/, "")
    this.popoverTextTarget.textContent = item.querySelector("span").textContent
    this.popoverPreviousTarget.disabled = index === 0
    this.popoverNextTarget.textContent = index === this.count - 1 ? "Done" : "Next"
    this.updateCount()

    const [ x, y, width, height ] = this.box(hotspot)
    const pad = 0.6
    Object.assign(this.spotlightTarget.style, {
      left: `${x - pad}%`, top: `${y - pad}%`, width: `${width + pad * 2}%`, height: `${height + pad * 2}%`
    })
    this.spotlightTarget.hidden = false
    this.popoverTarget.hidden = false
    this.place()
    // Keeps the keyboard in the walkthrough, so the arrow keys work after pressing a hotspot or Show me how.
    this.popoverNextTarget.focus({ preventScroll: true })
    this.popoverTarget.scrollIntoView({ block: "nearest", behavior: "smooth" })
  }

  finish() {
    this.index = null
    this.element.classList.remove("is-touring")
    this.popoverTarget.hidden = true
    this.spotlightTarget.hidden = true
    this.startTarget.hidden = false
    this.startTarget.querySelector("button").lastChild.textContent = " Show me again"
    this.startTarget.querySelector("button").focus({ preventScroll: true })
    this.hotspotTargets.forEach((each) => each.classList.remove("is-active"))
    this.itemTargets.forEach((each) => each.classList.remove("is-active"))
    this.updateCount()
  }

  // Puts the pop-up beside the current step, on whichever side it fits, with its arrow pointing at the step.
  place() {
    if (this.index === null) return
    const screen = this.stageTarget.querySelector(".walkthrough-screen")
    const stage = screen.getBoundingClientRect()
    const [ x, y, width, height ] = this.box(this.hotspotTargets[this.index]).map((value, i) => value / 100 * (i % 2 ? stage.height : stage.width))
    const target = { left: x, top: y, right: x + width, bottom: y + height, centerX: x + width / 2, centerY: y + height / 2 }
    const popover = this.popoverTarget
    const { GAP, MARGIN, DOCK_BELOW } = this.constructor

    popover.classList.toggle("is-docked", stage.width < DOCK_BELOW)
    popover.style.left = popover.style.top = ""
    if (stage.width < DOCK_BELOW) {
      this.pointArrow("top", { left: this.clamp(target.centerX, 16, stage.width - 16) })
      return
    }

    const size = { width: popover.offsetWidth, height: popover.offsetHeight }
    const across = this.clamp(target.centerX - size.width / 2, MARGIN, stage.width - size.width - MARGIN)
    const down = this.clamp(target.centerY - size.height / 2, MARGIN, stage.height - size.height - MARGIN)
    const sides = [
      [ "below", target.bottom + GAP + size.height <= stage.height, { left: across, top: target.bottom + GAP } ],
      [ "above", target.top - GAP - size.height >= 0, { left: across, top: target.top - GAP - size.height } ],
      [ "right", target.right + GAP + size.width <= stage.width, { left: target.right + GAP, top: down } ],
      [ "left", target.left - GAP - size.width >= 0, { left: target.left - GAP - size.width, top: down } ]
    ]
    const [ side, , position ] = sides.find(([ , fits ]) => fits) || [ "below", true, { left: across, top: target.bottom + GAP } ]

    popover.style.left = `${screen.offsetLeft + position.left}px`
    popover.style.top = `${screen.offsetTop + position.top}px`
    const edge = { below: "top", above: "bottom", right: "left", left: "right" }[side]
    this.pointArrow(edge, side === "below" || side === "above"
      ? { left: this.clamp(target.centerX - position.left, 16, size.width - 16) }
      : { top: this.clamp(target.centerY - position.top, 16, size.height - 16) })
  }

  pointArrow(edge, offset) {
    this.arrowTarget.dataset.edge = edge
    this.arrowTarget.style.left = offset.left === undefined ? "" : `${offset.left}px`
    this.arrowTarget.style.top = offset.top === undefined ? "" : `${offset.top}px`
  }

  updateCount() {
    this.countTarget.textContent = this.index === null ? `${this.count} steps` : `${this.index + 1} / ${this.count}`
    this.previousTarget.disabled = !this.index
    this.nextTarget.disabled = this.index === this.count - 1
  }

  box(hotspot) {
    return hotspot.dataset.box.split(",").map(Number)
  }

  clamp(value, min, max) {
    return Math.min(Math.max(value, min), Math.max(min, max))
  }

  get count() {
    return this.hotspotTargets.length
  }
}
