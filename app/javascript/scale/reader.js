import { SettledWeight, splitLines } from "scale/weight"

// What a till's scale setting means on the wire. Scales that send all the time need nothing asked of them; the
// others answer a short command.
const REQUESTS = { continuous: null, request_w: "W\r", request_s: "S\r\n", request_q: "Q\r\n", request_p: "P\r\n" }
const FRAMINGS = { "8N1": { dataBits: 8, parity: "none" }, "7E1": { dataBits: 7, parity: "even" }, "7O1": { dataBits: 7, parity: "odd" } }

// Reads one settled weight, in kilograms, from the scale on this computer's serial port (Web Serial: Chrome and
// Edge). The first time, the browser asks which port; after that it remembers. The port is opened for the reading
// and closed again, so nothing is left holding it.
export async function readScale({ mode, baudRate, framing }, { serial = navigator.serial, timeout = 6000 } = {}) {
  if (!serial) throw new Error("This browser can't read a scale. Use Chrome or Edge on the till's computer, or type the weight")

  const port = (await serial.getPorts())[0] || await serial.requestPort()
  await port.open({ baudRate: baudRate || 9600, stopBits: 1, ...(FRAMINGS[framing] || FRAMINGS["8N1"]) })

  const request = REQUESTS[mode]
  const settled = new SettledWeight(request ? 1 : 3)
  const reader = port.readable.getReader()
  const decoder = new TextDecoder("ascii")
  let timedOut = false
  const timer = setTimeout(() => { timedOut = true; reader.cancel().catch(() => {}) }, timeout)
  // A scale still moving answers a request with a status rather than a weight, so it's asked again until it settles.
  const asking = request && setInterval(() => send(port, request), 700)

  try {
    if (request) await send(port, request)
    let buffer = ""
    while (true) {
      const { value, done } = await reader.read()
      if (done) break
      // Scales set to seven data bits may still leave the parity bit on.
      buffer += decoder.decode(value.map((byte) => byte & 0x7f), { stream: true })
      const { lines, rest } = splitLines(buffer)
      buffer = rest
      for (const line of lines) {
        const kilograms = settled.feed(line)
        if (kilograms) return kilograms
      }
    }
    if (settled.seen === undefined) throw new Error("Nothing came from the scale. Check it's switched on and plugged in, and its settings in Settings › Tills")
    throw new Error(settled.seen <= 0 ? "Nothing is on the scale" : "The scale didn't settle. Try again")
  } finally {
    clearTimeout(timer)
    clearInterval(asking)
    if (!timedOut) await reader.cancel().catch(() => {})
    reader.releaseLock()
    await port.close().catch(() => {})
  }
}

async function send(port, text) {
  if (!port.writable || port.writable.locked) return
  const writer = port.writable.getWriter()
  try {
    await writer.write(new TextEncoder().encode(text))
  } catch {
    // The port closed under us: the reading has finished one way or the other.
  } finally {
    writer.releaseLock()
  }
}
