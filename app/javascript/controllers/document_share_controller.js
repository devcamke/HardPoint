import { Controller } from "@hotwired/stimulus"

// Turns a document's PDF (quote, invoice, credit note, receipt) into a sharp JPEG in the browser, then shares it through
// the device's own share sheet (WhatsApp, Telegram, email, Bluetooth…) or saves it. Nothing leaves the device except
// what the person chooses to share. pdf.js is loaded only when it's first needed.
export default class extends Controller {
  static values = { pdf: String, name: String, title: String, text: String, worker: String }
  static targets = [ "status", "menu" ]

  // The menu opens towards whichever side has room, so it never runs off the screen.
  place() {
    if (!this.hasMenuTarget || this.menuTarget.hidden) return
    const menu = this.menuTarget
    menu.style.left = "0px"
    menu.style.right = "auto"
    if (menu.getBoundingClientRect().right > window.innerWidth - 8) {
      menu.style.left = "auto"
      menu.style.right = "0px"
    }
  }

  async sharePicture() {
    await this.#run("Making the picture…", async () => this.#share(await this.#picture(), "picture"))
  }

  async savePicture() {
    await this.#run("Making the picture…", async () => this.#download(await this.#picture()))
  }

  async sharePdf() {
    await this.#run("Getting the PDF…", async () => this.#share(new File([ await this.#pdfBytes() ], `${this.nameValue}.pdf`, { type: "application/pdf" }), "PDF"))
  }

  async #run(message, work) {
    this.#say(message)
    try {
      await work()
    } catch (error) {
      if (error?.name === "AbortError") return this.#say("")
      console.error(error)
      this.#say("That didn't work. Try Download PDF instead.")
    }
  }

  async #share(file, kind) {
    if (navigator.canShare?.({ files: [ file ] })) {
      await navigator.share({ files: [ file ], title: this.titleValue, text: this.textValue || undefined })
      this.#say("")
    } else {
      this.#download(file)
      this.#say(`Saved the ${kind}. This browser can't share files directly: attach it in WhatsApp Web, email or any app.`)
    }
  }

  #download(file) {
    const url = URL.createObjectURL(file)
    const link = Object.assign(document.createElement("a"), { href: url, download: file.name })
    document.body.append(link)
    link.click()
    link.remove()
    setTimeout(() => URL.revokeObjectURL(url), 10_000)
    this.#say(`Saved ${file.name}.`)
  }

  async #pdfBytes() {
    this.bytes ||= await fetch(this.pdfValue, { credentials: "same-origin" }).then((response) => {
      if (!response.ok) throw new Error(`PDF ${response.status}`)
      return response.arrayBuffer()
    })
    return this.bytes.slice(0)
  }

  // Every page, one under the other, about 1,600 pixels wide (a receipt's roll about 1,100): sharp on any phone.
  async #picture() {
    const pdfjs = await import("pdfjs-dist")
    pdfjs.GlobalWorkerOptions.workerSrc = this.workerValue
    const doc = await pdfjs.getDocument({ data: await this.#pdfBytes() }).promise
    const pages = []
    for (let number = 1; number <= Math.min(doc.numPages, 6); number++) {
      const page = await doc.getPage(number)
      const [ , , width ] = page.view
      const viewport = page.getViewport({ scale: (width < 300 ? 1100 : 1600) / width })
      const canvas = Object.assign(document.createElement("canvas"), { width: Math.ceil(viewport.width), height: Math.ceil(viewport.height) })
      const context = canvas.getContext("2d")
      context.fillStyle = "#ffffff"
      context.fillRect(0, 0, canvas.width, canvas.height)
      await page.render({ canvasContext: context, viewport }).promise
      // The last page is cut below its last line, so a short quote isn't mostly empty paper in a chat.
      pages.push(number === Math.min(doc.numPages, 6) ? this.#trimmed(canvas) : canvas)
    }
    const gap = 24
    const sheet = Object.assign(document.createElement("canvas"), {
      width: Math.max(...pages.map((page) => page.width)),
      height: pages.reduce((sum, page) => sum + page.height, 0) + gap * (pages.length - 1)
    })
    const context = sheet.getContext("2d")
    context.fillStyle = "#e5e7eb"
    context.fillRect(0, 0, sheet.width, sheet.height)
    let top = 0
    for (const page of pages) { context.drawImage(page, 0, top); top += page.height + gap }
    const blob = await new Promise((resolve) => sheet.toBlob(resolve, "image/jpeg", 0.92))
    return new File([ blob ], `${this.nameValue}.jpg`, { type: "image/jpeg" })
  }

  #trimmed(canvas) {
    const context = canvas.getContext("2d")
    const { width, height } = canvas
    const pixels = context.getImageData(0, 0, width, height).data
    let last = height - 1
    rows: for (; last > 0; last--) {
      for (let x = 0, i = last * width * 4; x < width; x += 2, i += 8) {
        if (pixels[i] < 245 || pixels[i + 1] < 245 || pixels[i + 2] < 245) break rows
      }
    }
    const keep = Math.min(height, last + Math.round(width * 0.06))
    if (keep >= height - 4) return canvas
    const cut = Object.assign(document.createElement("canvas"), { width, height: keep })
    cut.getContext("2d").drawImage(canvas, 0, 0)
    return cut
  }

  #say(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }
}
