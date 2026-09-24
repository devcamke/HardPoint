// Printing straight to a receipt printer (and opening its drawer) through QZ Tray, the print
// agent installed on the till's computer. QZ Tray's script is loaded only when a till uses it.
import { receipt, commands, toBase64 } from "offline/escpos"

let loading

function loadQz() {
  if (window.qz) return Promise.resolve(window.qz)
  loading ||= new Promise((resolve, reject) => {
    const script = document.createElement("script")
    script.src = document.querySelector("meta[name=qz-tray-src]").content
    script.onload = () => resolve(window.qz)
    script.onerror = () => reject(new Error("QZ Tray's script couldn't be loaded"))
    document.head.append(script)
  })
  return loading
}

// Signed requests print without QZ Tray asking each time; with no certificate set up, QZ Tray
// asks the cashier once to allow this site.
async function connect() {
  const qz = await loadQz()
  if (qz.websocket.isActive()) return qz

  qz.security.setCertificatePromise((resolve) => fetch("/qz_certificate").then((response) => response.ok ? response.text() : "").then(resolve, () => resolve("")))
  qz.security.setSignatureAlgorithm("SHA512")
  qz.security.setSignaturePromise((toSign) => (resolve) => {
    const token = document.querySelector("meta[name=csrf-token]")?.content
    fetch("/qz_signature", { method: "POST", headers: { "X-CSRF-Token": token, "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ request: toSign }) })
      .then((response) => response.ok ? response.text() : "").then(resolve, () => resolve(""))
  })
  await qz.websocket.connect()
  return qz
}

async function send(printerName, bytes) {
  const qz = await connect()
  await qz.print(qz.configs.create(printerName), [ { type: "raw", format: "base64", data: toBase64(bytes) } ])
}

export function printReceipt(data, till) {
  return send(till.printer_name, receipt(data, { width: till.receipt_width || 48 }))
}

export function openDrawer(printerName) {
  return send(printerName, Uint8Array.from(commands.openDrawer))
}
