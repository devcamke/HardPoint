// What scales send, and what the till makes of it:
//   node --test test/javascript/
import { test } from "node:test"
import assert from "node:assert/strict"
import { parseWeight, SettledWeight, splitLines, inUnit } from "../../app/javascript/scale/weight.js"

test("a weight is read from the formats shop scales send", () => {
  assert.deepEqual(parseWeight("ST,GS,+0001.234kg"), { kilograms: 1.234, stable: true })
  assert.deepEqual(parseWeight("US,GS,+0001.200kg"), { kilograms: 1.2, stable: false })
  assert.deepEqual(parseWeight("ST,NT,  12.50 kg"), { kilograms: 12.5, stable: true })
  assert.deepEqual(parseWeight("S S      1.234 kg"), { kilograms: 1.234, stable: true })
  assert.deepEqual(parseWeight("S D      1.100 kg"), { kilograms: 1.1, stable: false })
  assert.deepEqual(parseWeight("\x02 01.234"), { kilograms: 1.234, stable: null })
  assert.deepEqual(parseWeight("   0.750 kg"), { kilograms: 0.75, stable: null })
  assert.deepEqual(parseWeight("   0.750 kg ?"), { kilograms: 0.75, stable: false })
  assert.deepEqual(parseWeight("1,5 kg"), { kilograms: 1.5, stable: null }, "a decimal comma")
  assert.deepEqual(parseWeight("ST,GS,-0000.020kg"), { kilograms: -0.02, stable: true })
})

test("grams, pounds and ounces come out as kilograms", () => {
  assert.equal(parseWeight("ST,+00750.0  g").kilograms, 0.75)
  assert.equal(parseWeight("S S    250 g").kilograms, 0.25)
  assert.equal(parseWeight("2.205 lb").kilograms, 1.000171)
  assert.equal(parseWeight("16 oz").kilograms, 0.453592)
  assert.equal(parseWeight("0500", "g").kilograms, 0.5, "no unit sent: the scale's own")
})

test("lines without a weight are passed over", () => {
  assert.equal(parseWeight(""), null)
  assert.equal(parseWeight("\x02?D"), null, "a Toledo status byte while the pan moves")
  assert.equal(parseWeight("OL"), null, "overloaded")
  assert.equal(parseWeight("S I"), null, "SICS: can't weigh now")
  assert.equal(parseWeight("S +"), null, "SICS: overload")
  assert.equal(parseWeight("READY"), null)
})

test("a weight counts once the scale says it's stable", () => {
  const settled = new SettledWeight()
  assert.equal(settled.feed("US,GS,+0001.100kg"), null)
  assert.equal(settled.feed("US,GS,+0001.230kg"), null)
  assert.equal(settled.feed("ST,GS,+0001.234kg"), 1.234)
})

test("a scale that doesn't say has to repeat itself; a change starts the count again", () => {
  const settled = new SettledWeight(3)
  assert.equal(settled.feed("  1.200 kg"), null)
  assert.equal(settled.feed("  1.234 kg"), null)
  assert.equal(settled.feed("  1.234 kg"), null)
  assert.equal(settled.feed("  1.234 kg"), 1.234)

  const asked = new SettledWeight(1)
  assert.equal(asked.feed("\x02?D"), null)
  assert.equal(asked.feed("\x02 02.500"), 2.5, "an answer to a request is settled already")
})

test("an empty pan or a minus reading never settles", () => {
  const settled = new SettledWeight(1)
  assert.equal(settled.feed("ST,GS,+0000.000kg"), null)
  assert.equal(settled.feed("ST,GS,-0000.020kg"), null)
  assert.equal(settled.seen, -0.02)
})

test("bytes are cut into lines at CR, LF and ETX, keeping a half-sent line for later", () => {
  assert.deepEqual(splitLines("ST,GS,+0001.234kg\r\nUS,GS,+00"), { lines: [ "ST,GS,+0001.234kg" ], rest: "US,GS,+00" })
  assert.deepEqual(splitLines("\x02 01.234\r\x02 01.2"), { lines: [ "\x02 01.234" ], rest: "\x02 01.2" })
  assert.deepEqual(splitLines("\r\n\r\n"), { lines: [], rest: "" })
})

test("the weight goes on the sale in the product's unit, to three places", () => {
  assert.equal(inUnit(1.2344, 1), 1.234)
  assert.equal(inUnit(0.75, 1000), 750)
  assert.equal(inUnit(0.1 + 0.2, 1), 0.3)
})
