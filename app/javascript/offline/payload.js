// What the offline till tells the server about a sale's money and its number, kept apart from
// the screen so the sums can be tested on their own.

// Cash pays what the till charged and no more. The server may price the sale higher when it's sent
// (a hand discount it won't take, a price it works out differently), but the change was already
// handed over from this drawer, so the extra would only overstate the cash in it. Other tenders pay
// exactly what was due; their code is checked once the till is back online.
export function offlinePayments(tender, due, tendered, reference) {
  if (!(due > 0)) return []
  if (tender === "cash") return [ { tender, amount_cents: Math.min(tendered, due), tendered_cents: tendered, reference: null } ]
  return [ { tender, amount_cents: due, tendered_cents: null, reference: reference || null } ]
}

// Offline receipt numbers run per till, per device: MAIN-OFF3-K7Q2-0001 is the first sale rung up
// offline on till 3 by the device calling itself K7Q2. Two tablets on one till, or a browser whose
// storage was cleared, each count from one again, so the device's code keeps their numbers apart.
// The server gives the sale its real number when it's sent; the offline number stays searchable.
export function offlineReceiptNumber(till, deviceCode, counter) {
  return `${till.branch_code}-OFF${till.register_id}-${deviceCode}-${String(counter).padStart(4, "0")}`
}

// A device's code: four characters, leaving out the letters and digits that get misread (0 and O, 1 and I).
const DEVICE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"

export function deviceCode(randomBytes = crypto.getRandomValues(new Uint8Array(4))) {
  return Array.from(randomBytes, (byte) => DEVICE_ALPHABET[byte % DEVICE_ALPHABET.length]).join("")
}
