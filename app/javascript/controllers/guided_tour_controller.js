import { Controller } from "@hotwired/stimulus"

// A guided tour over the live screen (shared/_guided_tour, tours defined in config/help_tours.yml): the rest of the
// screen dims, the step's button is lit up, and a pop-up with an arrow says what it does. Steps whose target isn't
// showing (hidden for this role, a feature that's off, or a phone layout) are skipped.
//
// The tour is kept in sessionStorage until it has run, so one whose screen is a step away (the till sends you to
// choose a till or open a shift first) starts when you get there.
const STORAGE_KEY = "hardpoint:guided-tour"
const PENDING_FOR = 15 * 60 * 1000
const GAP = 14
const MARGIN = 12
const PAD = 6

export default class extends Controller {
  static values = { tour: Object, toursUrl: String, path: String }

  connect() {
    this.onStartLink = (event) => this.saveFromLink(event)
    document.addEventListener("click", this.onStartLink, true)

    let tour = this.pending
    if (this.hasTourValue && this.tourValue.id) {
      tour = { ...this.tourValue, savedAt: Date.now() }
      this.store(tour)
      this.removeTourFromAddress()
    }

    if (!tour) return
    // The page's own path, from the server: after a redirect, Turbo renders before it updates the address bar.
    if (this.pathValue === tour.page) {
      this.whenDrawn(tour, () => this.start(tour))
    } else {
      this.showWaiting(tour)
    }
  }

  disconnect() {
    clearTimeout(this.timer)
    document.removeEventListener("click", this.onStartLink, true)
    this.teardown()
  }

  // Links made by link_to_tour carry their tour, saved here as they're pressed: the page they go to may redirect
  // (to choose a till, say) and lose the ?tour= on the way.
  saveFromLink(event) {
    const link = event.target.closest?.("a[data-guided-tour-start]")
    if (!link) return
    try { this.store({ ...JSON.parse(link.dataset.guidedTourStart), savedAt: Date.now() }) } catch { /* the ?tour= still works */ }
  }

  // Parts of some screens load after the page (the till's products), so wait a moment for every step to show.
  whenDrawn(tour, callback, waited = 0) {
    const ready = tour.steps.every((step) => this.visible(this.find(step)))
    if (ready || waited >= 3000) callback()
    else this.timer = setTimeout(() => this.whenDrawn(tour, callback, waited + 150), 150)
  }

  start(tour) {
    this.clearPending()
    this.tour = tour
    this.steps = tour.steps.filter((step) => this.visible(this.find(step)))
    this.index = 0
    this.build()

    if (this.steps.length === 0) {
      this.showMessage(tour.title, "This tour's buttons aren't on this screen for you. Try it on a bigger screen, or read the guide instead.")
    } else {
      this.go(0)
    }
  }

  // Building and tearing down the tour's own elements, outside the page's markup.

  build() {
    this.blocker = this.element.ownerDocument.createElement("div")
    this.blocker.className = "guided-tour-blocker"
    this.spotlight = this.element.ownerDocument.createElement("div")
    this.spotlight.className = "guided-tour-spotlight"
    this.popover = this.element.ownerDocument.createElement("div")
    this.popover.className = "guided-tour-popover"
    this.popover.setAttribute("role", "dialog")
    this.popover.setAttribute("aria-modal", "true")
    this.popover.setAttribute("aria-label", `Guided tour: ${this.tour.title}`)
    document.body.append(this.blocker, this.spotlight, this.popover)

    this.onKeydown = (event) => this.keydown(event)
    this.onReposition = () => this.place()
    document.addEventListener("keydown", this.onKeydown, true)
    window.addEventListener("resize", this.onReposition)
    window.addEventListener("scroll", this.onReposition, true)
    this.blocker.addEventListener("click", () => this.popover.querySelector("[data-primary]")?.focus())
  }

  teardown() {
    this.blocker?.remove()
    this.spotlight?.remove()
    this.popover?.remove()
    this.waiting?.remove()
    this.blocker = this.spotlight = this.popover = this.waiting = null
    document.removeEventListener("keydown", this.onKeydown, true)
    window.removeEventListener("resize", this.onReposition)
    window.removeEventListener("scroll", this.onReposition, true)
  }

  // Moving through the steps.

  go(index) {
    this.index = index
    const step = this.steps[index]
    const last = index === this.steps.length - 1

    this.popover.classList.remove("is-centred")
    this.blocker.classList.remove("is-dimmed")
    this.popover.innerHTML = `
      <span class="guided-tour-arrow" aria-hidden="true"></span>
      <div class="flex items-start justify-between gap-3">
        <p class="walkthrough-popover-step">${this.escape(this.tour.title)} · ${index + 1} of ${this.steps.length}</p>
        <button type="button" class="-mt-1 -mr-1 cursor-pointer rounded px-1.5 text-lg leading-none text-gray-400 hover:bg-gray-100 hover:text-gray-700" data-action="end" aria-label="End the tour">×</button>
      </div>
      <p class="walkthrough-popover-title">${this.escape(step.title)}</p>
      <p class="walkthrough-popover-text">${this.escape(step.text)}</p>
      <div class="walkthrough-popover-actions">
        <button type="button" class="walkthrough-link" data-action="back" ${index === 0 ? "disabled" : ""}>Back</button>
        <span class="walkthrough-dots" aria-hidden="true">${this.steps.map((_, i) => `<span class="${i === index ? "is-active" : ""}"></span>`).join("")}</span>
        <button type="button" class="walkthrough-next" data-action="${last ? "finish" : "next"}" data-primary>${last ? "Done" : "Next"}</button>
      </div>`
    this.bindButtons()

    const target = this.find(step)
    const rect = target.getBoundingClientRect()
    const offScreen = rect.top < 60 || rect.bottom > window.innerHeight - 20
    if (offScreen) target.scrollIntoView({ block: "center", behavior: this.reducedMotion ? "auto" : "smooth" })
    this.spotlight.hidden = false
    this.place()
    if (offScreen) setTimeout(() => this.place(), 400)
    this.popover.querySelector("[data-primary]").focus({ preventScroll: true })
  }

  finish() {
    this.showMessage("That's the tour", "You can take it again, or another one, from Guided tours under your name. The guide has the rest.", true)
  }

  end() {
    this.teardown()
  }

  showMessage(title, text, finished = false) {
    this.index = null
    this.spotlight.hidden = true
    this.blocker.classList.add("is-dimmed")
    this.popover.classList.add("is-centred")
    this.popover.style.left = this.popover.style.top = ""
    this.popover.innerHTML = `
      ${finished ? `<p class="text-3xl" aria-hidden="true">🎉</p>` : ""}
      <p class="walkthrough-popover-title">${this.escape(title)}</p>
      <p class="walkthrough-popover-text">${this.escape(text)}</p>
      <div class="mt-4 flex flex-wrap items-center justify-end gap-3">
        <a class="link text-sm" href="${this.escape(this.tour.guide_url)}" target="_blank" rel="noopener">Read the guide ↗</a>
        <a class="link text-sm" href="${this.escape(this.toursUrlValue)}">More tours</a>
        <button type="button" class="walkthrough-next" data-action="end" data-primary>Close</button>
      </div>`
    this.bindButtons()
    this.popover.querySelector("[data-primary]").focus()
  }

  // While waiting to reach the tour's screen: a note in the corner, with a way out.
  showWaiting(tour) {
    this.waiting = this.element.ownerDocument.createElement("div")
    this.waiting.className = "fixed right-4 bottom-4 z-[1001] flex max-w-sm items-center gap-3 rounded-lg border border-gray-200 bg-white px-4 py-3 text-sm shadow-xl"
    this.waiting.setAttribute("role", "status")
    this.waiting.innerHTML = `
      <span class="flex size-6 shrink-0 items-center justify-center rounded-full bg-[#e46f2f] text-xs font-bold text-white" aria-hidden="true">?</span>
      <p><strong>${this.escape(tour.title)}</strong> starts when you get to its screen.</p>
      <button type="button" class="link shrink-0 cursor-pointer" data-action="cancel">Cancel</button>`
    this.waiting.querySelector("[data-action=cancel]").addEventListener("click", () => { this.clearPending(); this.teardown() })
    document.body.append(this.waiting)
  }

  bindButtons() {
    this.popover.querySelectorAll("[data-action]").forEach((button) => {
      button.addEventListener("click", () => ({
        next: () => this.go(this.index + 1),
        back: () => this.go(this.index - 1),
        finish: () => this.finish(),
        end: () => this.end()
      })[button.dataset.action]())
    })
  }

  keydown(event) {
    if (!this.popover) return
    if (event.key === "Escape") { this.end() }
    else if (this.index === null) { return }
    else if (event.key === "ArrowRight" || (event.key === "Enter" && event.target === this.popover.querySelector("[data-primary]"))) {
      this.index < this.steps.length - 1 ? this.go(this.index + 1) : this.finish()
    } else if (event.key === "ArrowLeft" && this.index > 0) { this.go(this.index - 1) }
    else if (event.key === "Tab") { this.trapFocus(event); return }
    else { return }
    // The till listens for F-keys and typing to scan; none of it should reach the page while the tour is up.
    event.preventDefault()
    event.stopPropagation()
  }

  trapFocus(event) {
    const buttons = [ ...this.popover.querySelectorAll("button:not([disabled]), a") ]
    const position = buttons.indexOf(document.activeElement)
    const next = event.shiftKey ? (position <= 0 ? buttons.length - 1 : position - 1) : (position + 1) % buttons.length
    buttons[next].focus()
    event.preventDefault()
  }

  // Lights up the step's target and puts the pop-up beside it, on whichever side has room.
  place() {
    if (this.index === null || !this.popover) return
    const target = this.find(this.steps[this.index])
    if (!target) return
    const rect = target.getBoundingClientRect()
    const box = {
      left: Math.max(rect.left - PAD, 4), top: Math.max(rect.top - PAD, 4),
      right: Math.min(rect.right + PAD, window.innerWidth - 4), bottom: Math.min(rect.bottom + PAD, window.innerHeight - 4)
    }
    Object.assign(this.spotlight.style, {
      left: `${box.left}px`, top: `${box.top}px`, width: `${box.right - box.left}px`, height: `${box.bottom - box.top}px`
    })

    const size = { width: this.popover.offsetWidth, height: this.popover.offsetHeight }
    const view = { width: window.innerWidth, height: window.innerHeight }
    const centreX = (box.left + box.right) / 2
    const centreY = (box.top + box.bottom) / 2
    const across = this.clamp(centreX - size.width / 2, MARGIN, view.width - size.width - MARGIN)
    const down = this.clamp(centreY - size.height / 2, MARGIN, view.height - size.height - MARGIN)
    const sides = [
      [ "below", box.bottom + GAP + size.height <= view.height - MARGIN, across, box.bottom + GAP ],
      [ "above", box.top - GAP - size.height >= MARGIN, across, box.top - GAP - size.height ],
      [ "left", box.left - GAP - size.width >= MARGIN, box.left - GAP - size.width, down ],
      [ "right", box.right + GAP + size.width <= view.width - MARGIN, box.right + GAP, down ]
    ]
    // A target bigger than the screen has room on no side: the pop-up goes over its bottom edge.
    const [ side, , left, top ] = sides.find(([ , fits ]) => fits) ||
      [ "above", true, across, this.clamp(box.bottom - size.height - GAP, MARGIN, view.height - size.height - MARGIN) ]

    this.popover.style.left = `${left}px`
    this.popover.style.top = `${top}px`
    const arrow = this.popover.querySelector(".guided-tour-arrow")
    arrow.dataset.edge = { below: "top", above: "bottom", right: "left", left: "right" }[side]
    arrow.style.left = side === "below" || side === "above" ? `${this.clamp(centreX - left, 16, size.width - 16)}px` : ""
    arrow.style.top = side === "left" || side === "right" ? `${this.clamp(centreY - top, 16, size.height - 16)}px` : ""
  }

  // Helpers

  find(step) {
    return document.querySelector(`[data-tour="${CSS.escape(step.target)}"]`)
  }

  visible(element) {
    if (!element) return false
    const rect = element.getBoundingClientRect()
    return rect.width > 0 && rect.height > 0 && getComputedStyle(element).visibility !== "hidden"
  }

  removeTourFromAddress() {
    const url = new URL(location.href)
    url.searchParams.delete("tour")
    history.replaceState(history.state, "", url)
  }

  get pending() {
    try {
      const tour = JSON.parse(sessionStorage.getItem(STORAGE_KEY))
      return tour && Date.now() - tour.savedAt < PENDING_FOR ? tour : null
    } catch {
      return null
    }
  }

  store(tour) {
    try { sessionStorage.setItem(STORAGE_KEY, JSON.stringify(tour)) } catch { /* the tour still runs on this page */ }
  }

  clearPending() {
    try { sessionStorage.removeItem(STORAGE_KEY) } catch { /* nothing kept */ }
  }

  clamp(value, min, max) {
    return Math.min(Math.max(value, min), Math.max(min, max))
  }

  escape(text) {
    const div = document.createElement("div")
    div.textContent = text ?? ""
    return div.innerHTML.replace(/"/g, "&quot;")
  }

  get reducedMotion() {
    return matchMedia("(prefers-reduced-motion: reduce)").matches
  }
}
