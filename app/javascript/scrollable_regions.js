// A table wider than the screen scrolls sideways inside its box. Keyboard users can only scroll a box they can
// reach, so a box that really overflows joins the tab order (and is named after its table's caption or heading);
// one that fits stays out of the way.
function markScrollableRegions() {
  // On phones a card holding a table is the box that scrolls (see .card:has(> .table) in the stylesheet).
  for (const box of document.querySelectorAll(".overflow-x-auto, .card")) {
    const overflows = box.scrollWidth > box.clientWidth + 1
    if (overflows && !box.hasAttribute("tabindex")) {
      box.tabIndex = 0
      box.dataset.scrollableRegion = ""
      if (!box.hasAttribute("aria-label") && !box.hasAttribute("aria-labelledby")) {
        const heading = box.querySelector("caption, h2, h3") || box.closest("section")?.querySelector("h2, h3")
        box.setAttribute("role", "region")
        box.setAttribute("aria-label", heading?.textContent.trim() || "Scrollable table")
      }
    } else if (!overflows && box.hasAttribute("data-scrollable-region")) {
      box.removeAttribute("tabindex")
      box.removeAttribute("role")
      box.removeAttribute("aria-label")
      delete box.dataset.scrollableRegion
    }
  }
}

// Turbo fires the first turbo:load before this module runs, so the page already showing is marked now.
markScrollableRegions()
document.addEventListener("turbo:load", markScrollableRegions)
document.addEventListener("turbo:frame-load", markScrollableRegions)
window.addEventListener("resize", () => requestAnimationFrame(markScrollableRegions))
