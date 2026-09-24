// The till's offline storage in IndexedDB: the catalogue snapshot, sales waiting to be sent,
// and a few counters. Each shop is its own web origin, so shops never share this storage.
const NAME = "hardpoint-till"
const VERSION = 1

function open() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(NAME, VERSION)
    request.onupgradeneeded = () => {
      const db = request.result
      db.createObjectStore("catalogue")
      db.createObjectStore("sales", { keyPath: "uuid" })
      db.createObjectStore("meta")
    }
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })
}

async function run(storeName, mode, action) {
  const db = await open()
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(storeName, mode)
    const result = action(transaction.objectStore(storeName))
    // Reads hand back an IDBRequest; its result is the value (undefined for a missing key).
    transaction.oncomplete = () => { db.close(); resolve(result instanceof IDBRequest ? result.result : result) }
    transaction.onerror = () => { db.close(); reject(transaction.error) }
  })
}

export const catalogue = {
  get: () => run("catalogue", "readonly", (store) => store.get("current")),
  put: (value) => run("catalogue", "readwrite", (store) => store.put(value, "current"))
}

export const sales = {
  all: () => run("sales", "readonly", (store) => store.getAll()),
  put: (sale) => run("sales", "readwrite", (store) => store.put(sale)),
  remove: (uuid) => run("sales", "readwrite", (store) => store.delete(uuid)),
  async waiting() {
    return (await this.all()).filter((sale) => sale.status !== "sent").sort((a, b) => a.happened_at.localeCompare(b.happened_at))
  }
}

export const meta = {
  get: (key) => run("meta", "readonly", (store) => store.get(key)),
  put: (key, value) => run("meta", "readwrite", (store) => store.put(value, key)),
  // A counter for offline receipt numbers on this device, per till.
  async next(key) {
    const value = ((await this.get(key)) || 0) + 1
    await this.put(key, value)
    return value
  }
}
