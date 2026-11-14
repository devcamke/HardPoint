// Reading a weight out of what a shop scale sends down its serial cable. Scales differ, but nearly all send a line
// of text with the weight as a number, usually its unit, and often a word saying whether the pan has settled:
//
//   ST,GS,+0001.234kg     A&D, CAS and many others: ST is stable, US unstable, OL overloaded
//   S S      1.234 kg     Mettler Toledo (SICS): "S S" stable, "S D" still moving
//   \x02 01.234\r         Toledo 8217 and compatibles, answering "W"; "?" and a status byte while moving
//      1.234 kg           plain; a "?" marks an unsettled reading on Ohaus scales
//
// No DOM and no serial port here, so Node can test it (test/javascript/scale_test.mjs).

const PER_KILOGRAM = { kg: 1, g: 1000, lb: 2.2046226218, lbs: 2.2046226218, oz: 35.27396195 }

// { kilograms, stable } for a line with a weight in it: stable is true or false when the scale says, null when it
// doesn't. null for a line with no weight (a status, an overload, noise).
export function parseWeight(line, defaultUnit = "kg") {
  const text = String(line).replace(/[\x00-\x1f\x7f]/g, " ").trim()
  if (!text || /^(OL|S\s+[+\-I])(\W|$)/i.test(text)) return null

  const numbers = [ ...text.matchAll(/([+-]?)\s*(\d+(?:[.,]\d+)?)\s*(kg|g|lbs?|oz)?(?![a-z])/gi) ]
  const match = numbers.find((number) => number[3]) || numbers.at(-1)
  if (!match) return null

  const value = parseFloat(match[2].replace(",", ".")) * (match[1] === "-" ? -1 : 1)
  const kilograms = value / PER_KILOGRAM[(match[3] || defaultUnit).toLowerCase()]
  let stable = null
  if (/^(ST|S\s+S)(\W|$)/i.test(text)) stable = true
  if (/^(US|S\s+D)(\W|$)/i.test(text) || text.includes("?")) stable = false
  return { kilograms: Math.round(kilograms * 1e6) / 1e6, stable }
}

// Fed each line as it arrives; answers with the weight in kilograms once it has settled, and null until then.
// A scale that says "stable" is believed at once. One that doesn't has to repeat the same weight `repeats` times.
// An empty pan never settles: nothing is sold by weighing nothing.
export class SettledWeight {
  constructor(repeats = 3) {
    this.repeats = repeats
    this.last = null
    this.count = 0
  }

  feed(line) {
    const reading = parseWeight(line)
    if (!reading) return null
    this.seen = reading.kilograms

    if (reading.stable === false || reading.kilograms <= 0) {
      this.last = null
      this.count = 0
      return null
    }
    if (reading.stable) return reading.kilograms

    this.count = reading.kilograms === this.last ? this.count + 1 : 1
    this.last = reading.kilograms
    return this.count >= this.repeats ? reading.kilograms : null
  }
}

// Bytes from the port, cut into lines at CR, LF or ETX; what's left waits for the rest of its line.
export function splitLines(buffer) {
  const parts = buffer.split(/[\r\n\x03]+/)
  return { lines: parts.slice(0, -1).filter((line) => line.trim() !== ""), rest: parts.at(-1) }
}

// A weight in the unit a product is sold by, to the three decimal places quantities keep.
export function inUnit(kilograms, perKilogram) {
  return Math.round(kilograms * perKilogram * 1000) / 1000
}
