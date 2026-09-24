// A busy afternoon at the till: each virtual user is a cashier at their own till, ringing up sales of
// 3–6 scanned items, a product search now and then, and cash with change, with a few seconds between
// scans as at a real counter. Run perf/setup.rb first; see perf/README.md.
//
//   k6 run -e BASE=http://loadtest.localhost:3000 -e VUS=20 perf/till.js
import http from "k6/http"
import { check, sleep, fail } from "k6"
import { Trend, Counter } from "k6/metrics"
import exec from "k6/execution"

const data = JSON.parse(open("./loadtest.json"))
const BASE = __ENV.BASE || "http://loadtest.localhost:3000"
const VUS = Number(__ENV.VUS || 20)
const THINK = Number(__ENV.THINK || 1) // seconds between a cashier's actions; 0 for a stress test

export const options = {
  hosts: { "loadtest.localhost": "127.0.0.1" },
  noCookiesReset: true, // a cashier stays signed in from sale to sale
  scenarios: {
    tills: { executor: "ramping-vus", startVUs: 1, stages: [
      { duration: "30s", target: VUS }, { duration: __ENV.HOLD || "2m", target: VUS }, { duration: "10s", target: 0 } ] }
  },
  thresholds: {
    "http_req_failed": [ "rate<0.01" ],
    "http_req_duration{action:scan}": [ "p(95)<500" ],
    "http_req_duration{action:pay}": [ "p(95)<800" ],
    "http_req_duration{action:search}": [ "p(95)<500" ],
    "checks": [ "rate>0.99" ]
  }
}

const saleSeconds = new Trend("sale_duration_server", true)
const salesCompleted = new Counter("sales_completed")
let csrf = null

function token(res) {
  const match = res.body && res.body.match(/name="csrf-token" content="([^"]+)"/)
  return match ? match[1] : null
}

function turbo(extra = {}) {
  return { headers: Object.assign({ "X-CSRF-Token": csrf, Accept: "text/vnd.turbo-stream.html, text/html" }, extra) }
}

function signInAndOpenTill() {
  const till = data.tills[(exec.vu.idInTest - 1) % data.tills.length]
  let res = http.get(`${BASE}/session/new`)
  csrf = token(res)
  res = http.post(`${BASE}/session`, { authenticity_token: csrf, email_address: till.email, password: till.password })
  if (!check(res, { "signed in": (r) => !r.url.includes("/session") })) fail(`sign-in failed for ${till.email}`)

  res = http.get(`${BASE}/pos/till/new`)
  csrf = token(res)
  http.post(`${BASE}/pos/till`, { authenticity_token: csrf, register_id: till.register_id })
  res = http.get(`${BASE}/pos`)
  if (res.url.includes("/shifts/new")) {
    csrf = token(res)
    res = http.post(`${BASE}/shifts`, { authenticity_token: csrf, "shift[opening_float]": "5000" })
  }
  res = http.get(`${BASE}/pos`, { tags: { action: "till" } })
  csrf = token(res)
  check(res, { "till open": (r) => r.status === 200 && r.body.includes('id="cart"') })
}

export default function () {
  if (!csrf) signInAndOpenTill()

  let spent = 0
  const lines = 3 + Math.floor(Math.random() * 4)
  for (let i = 0; i < lines; i++) {
    if (Math.random() < 0.25) {
      const query = data.searches[Math.floor(Math.random() * data.searches.length)]
      const found = http.get(`${BASE}/pos/products?query=${query}`, { tags: { action: "search" }, headers: { Accept: "text/html" } })
      check(found, { "search ok": (r) => r.status === 200 })
      spent += found.timings.duration
      sleep(THINK * Math.random())
    }
    const code = data.barcodes[Math.floor(Math.random() * data.barcodes.length)]
    const scanned = http.post(`${BASE}/pos/lines`, { code: code }, Object.assign(turbo(), { tags: { action: "scan" } }))
    check(scanned, { "scan ok": (r) => r.status === 200 && r.body.includes("turbo-stream") })
    spent += scanned.timings.duration
    sleep(THINK * (0.5 + Math.random()))
  }

  const paid = http.post(`${BASE}/pos/payments`, { tender: "cash", tendered: "1000000" }, Object.assign(turbo(), { tags: { action: "pay" } }))
  const completed = check(paid, { "sale completed": (r) => r.status === 200 && /completed=\d+/.test(r.url) })
  spent += paid.timings.duration
  if (completed) {
    salesCompleted.add(1)
    saleSeconds.add(spent)
    const id = paid.url.match(/completed=(\d+)/)[1]
    const receipt = http.get(`${BASE}/sales/${id}/receipt`, { tags: { action: "receipt" } })
    check(receipt, { "receipt ok": (r) => r.status === 200 })
    csrf = token(paid) || csrf
  }
  sleep(THINK * 2)
}
