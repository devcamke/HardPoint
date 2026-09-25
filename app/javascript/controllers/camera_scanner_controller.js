import { Controller } from "@hotwired/stimulus"

// Scans barcodes with the phone's camera where the browser can (the BarcodeDetector API: Chrome
// on Android), and falls back to typing or a Bluetooth scanner everywhere else. A code found fills
// the code field and submits its form, then scanning pauses until the item is dealt with (the
// form in the result submits, or "Scan next" is pressed), so one shelf isn't counted twice.
export default class extends Controller {
  static targets = ["video", "input", "form", "start", "stop", "unsupported"]
  static values = { formats: { type: Array, default: ["ean_13", "ean_8", "upc_a", "upc_e", "code_128", "code_39", "qr_code"] } }

  connect() {
    this.supported = "BarcodeDetector" in window && !!navigator.mediaDevices?.getUserMedia
    this.startTargets.forEach(button => button.hidden = !this.supported)
    this.unsupportedTargets.forEach(note => note.hidden = this.supported)
    this.stopTargets.forEach(button => button.hidden = true)
  }

  disconnect() {
    this.stop()
  }

  async start() {
    if (!this.supported || this.stream) return

    try {
      const available = await BarcodeDetector.getSupportedFormats()
      this.detector = new BarcodeDetector({ formats: this.formatsValue.filter(format => available.includes(format)) })
      this.stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" }, audio: false })
    } catch (error) {
      this.unsupportedTargets.forEach(note => { note.hidden = false; note.textContent = "The camera isn't available. Allow camera access, or type the code." })
      return
    }

    this.videoTarget.srcObject = this.stream
    this.videoTarget.hidden = false
    await this.videoTarget.play()
    this.startTargets.forEach(button => button.hidden = true)
    this.stopTargets.forEach(button => button.hidden = false)
    this.paused = false
    this.timer = setInterval(() => this.detect(), 250)
  }

  stop() {
    clearInterval(this.timer)
    this.stream?.getTracks().forEach(track => track.stop())
    this.stream = null
    if (this.hasVideoTarget) this.videoTarget.hidden = true
    this.startTargets.forEach(button => button.hidden = !this.supported)
    this.stopTargets.forEach(button => button.hidden = true)
  }

  // After an item is saved, or when the person wants to move on.
  resume() {
    this.paused = false
    this.inputTarget.value = ""
    if (!this.stream) this.inputTarget.focus()
  }

  async detect() {
    if (this.paused || this.detecting || this.videoTarget.readyState < 2) return

    this.detecting = true
    try {
      const [barcode] = await this.detector.detect(this.videoTarget)
      if (barcode?.rawValue) this.found(barcode.rawValue)
    } catch (error) {
      // A frame that couldn't be read; try the next one.
    } finally {
      this.detecting = false
    }
  }

  found(code) {
    this.paused = true
    navigator.vibrate?.(60)
    this.inputTarget.value = code
    this.formTarget.requestSubmit()
  }
}
