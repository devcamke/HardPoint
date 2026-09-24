// Receipts as ESC/POS, the command language of thermal receipt printers, for printing straight to
// the printer through QZ Tray. Takes the receipt shape from /sales/:id/receipt.json (or the
// offline till's own) and a line width (48 characters on 80 mm paper, 32 on 58 mm).

const ESC = 0x1b
const GS = 0x1d

export const commands = {
  init: [ ESC, 0x40 ],
  alignLeft: [ ESC, 0x61, 0 ],
  alignCenter: [ ESC, 0x61, 1 ],
  boldOn: [ ESC, 0x45, 1 ],
  boldOff: [ ESC, 0x45, 0 ],
  doubleHeight: [ GS, 0x21, 0x01 ],
  normalSize: [ GS, 0x21, 0x00 ],
  // Pulse the cash drawer on pin 2 (the usual one): 50 ms on, 500 ms off.
  openDrawer: [ ESC, 0x70, 0, 25, 250 ],
  // Feed a little, then a partial cut.
  cut: [ GS, 0x56, 66, 3 ]
}

// Receipt printers' built-in character sets don't agree beyond ASCII, so text is reduced to it.
export function ascii(text) {
  return String(text ?? "").normalize("NFKD").replace(/[\u0300-\u036f]/g, "").replace(/\u2044/g, "/").replace(/[\u00d7]/g, "x").replace(/[\u2013\u2014]/g, "-")
    .replace(/[\u2018\u2019]/g, "'").replace(/[\u201c\u201d]/g, '"').replace(/[^\x20-\x7e\n]/g, "?")
}

export function wrap(text, width) {
  const words = ascii(text).split(/\s+/).filter(Boolean)
  const lines = []
  let line = ""
  for (const word of words) {
    if ((line + " " + word).trim().length > width) {
      if (line) lines.push(line)
      line = word.length > width ? word.slice(0, width) : word
    } else {
      line = (line + " " + word).trim()
    }
  }
  if (line) lines.push(line)
  return lines.length ? lines : [ "" ]
}

// "Total ............ 1,000.00": left text and right text on one line, the left cut to fit.
export function columns(left, right, width) {
  right = ascii(right)
  left = ascii(left).slice(0, Math.max(width - right.length - 1, 0))
  return left + " ".repeat(Math.max(width - left.length - right.length, 1)) + right
}

// A QR code printed by the printer itself (GS ( k), model 2, error correction M.
function qr(data, size = 5) {
  const bytes = [ ...new TextEncoder().encode(ascii(data)) ]
  const length = bytes.length + 3
  return [
    GS, 0x28, 0x6b, 4, 0, 0x31, 0x41, 0x32, 0x00,
    GS, 0x28, 0x6b, 3, 0, 0x31, 0x43, size,
    GS, 0x28, 0x6b, 3, 0, 0x31, 0x45, 0x31,
    GS, 0x28, 0x6b, length % 256, Math.floor(length / 256), 0x31, 0x50, 0x30, ...bytes,
    GS, 0x28, 0x6b, 3, 0, 0x31, 0x51, 0x30
  ]
}

export function receipt(data, { width = 48, openDrawer = data.open_drawer } = {}) {
  const out = []
  const text = (value) => out.push(...new TextEncoder().encode(ascii(value) + "\n"))
  const rule = () => text("-".repeat(width))
  const add = (bytes) => out.push(...bytes)

  add(commands.init)
  add(commands.alignCenter); add(commands.boldOn); add(commands.doubleHeight)
  wrap(data.header?.[0], width).forEach(text)
  add(commands.normalSize); add(commands.boldOff)
  ;(data.header || []).slice(1).forEach((line) => wrap(line, width).forEach(text))
  add(commands.alignLeft)
  rule()
  text(columns("Receipt", data.receipt_number || "", width))
  text(columns(data.time || "", data.register || "", width))
  if (data.cashier) text(columns("Served by", data.cashier, width))
  if (data.customer) text(columns("Customer", data.customer, width))
  if (data.offline) text("Recorded offline; sent when the till is back online.")
  if (data.voided) { add(commands.alignCenter); text("*** VOIDED ***"); add(commands.alignLeft) }
  rule()
  for (const line of data.lines || []) {
    wrap(line.description, width).forEach(text)
    text(columns("  " + line.detail, line.total, width))
    if (line.discount) text(columns("  discount", "-" + line.discount, width))
  }
  rule()
  if (data.subtotal) text(columns("Subtotal", data.subtotal, width))
  if (data.discount) text(columns("Discount", "-" + data.discount, width))
  add(commands.boldOn); add(commands.doubleHeight)
  text(columns("TOTAL", data.total, width))
  add(commands.normalSize); add(commands.boldOff)
  text(columns("Incl. tax", data.tax, width))
  rule()
  for (const payment of data.payments || []) text(columns(payment.label, payment.amount, width))
  if (data.change) { add(commands.boldOn); text(columns("Change", data.change, width)); add(commands.boldOff) }
  if (data.etims) {
    rule()
    add(commands.alignCenter)
    data.etims.lines.forEach((line) => wrap(line, width).forEach(text))
    if (data.etims.qr) add(qr(data.etims.qr))
    add(commands.alignLeft)
  }
  rule()
  add(commands.alignCenter)
  wrap(data.footer, width).forEach(text)
  text("\n\n")
  add(commands.cut)
  if (openDrawer) add(commands.openDrawer)
  return Uint8Array.from(out)
}

export function toBase64(bytes) {
  let binary = ""
  bytes.forEach((byte) => { binary += String.fromCharCode(byte) })
  return btoa(binary)
}
