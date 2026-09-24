# Load testing the till

`till.js` is a [k6](https://k6.io) scenario: each virtual user is a cashier signed in at their own till,
ringing up sales of 3–6 scanned items (a product search a quarter of the time) and taking cash, with
about a second between actions (`THINK`, in seconds). That is several times faster than a real
counter, where a cashier scans every few seconds and serves a customer every couple of minutes.

```sh
TILLS=40 bin/rails runner perf/setup.rb          # the "loadtest" shop: 40 tills and cashiers, 2,000 products
PERF=1 WEB_CONCURRENCY=4 RAILS_MAX_THREADS=5 bin/rails server   # development, but no reloading and quiet logs
k6 run -e VUS=40 -e HOLD=2m perf/till.js
```

Against a staging server use `-e BASE=https://loadtest.staging.example` and run `perf/setup.rb` there
(never in production: it refuses).

Thresholds (the run fails if missed): no more than 1% of requests failing, 95% of scans and searches
under 500 ms and payments (which complete the sale: stock, costs, receipt number, eTIMS queue) under 800 ms.

## Results, 24 September 2026

One 4-core container running the app, PostgreSQL 16 and k6 together, so the numbers are conservative
for a dedicated 6-core VPS.

| Setup | Cashiers | Requests/s | Scan p95 | Search p95 | Payment p95 | Sales | Errors |
|---|---|---|---|---|---|---|---|
| 1 Puma process, 5 threads | 20 | 14.5 | 784 ms | 683 ms | 1.12 s | 1.4/s | 0 |
| 4 Puma workers × 5 threads | 40 | 38.3 | 278 ms | 232 ms | 638 ms | 4.2/s | 0 |

One Ruby process serves about 14 till requests a second (each costs roughly 70 ms of CPU), so the
work spreads by adding Puma workers, one per core. At 4.2 sales a second the 4-worker run sold 15,000
sales an hour; 40 real cashiers make about one sale every 2 minutes each, 0.3 a second, so there
is room for roughly ten times that many tills before the server is the limit.

What the runs turned up, and what changed:

- **Sign-in rate limit per address.** Every till in a shop reaches the internet through the shop's
  router, so they share one public address; the limit of 10 sign-ins per 3 minutes per address locked
  out half the cashiers at a shift change. Sign-in is now limited per login (10 per 3 minutes) with a
  looser 60 per address; PIN switching, two-factor codes and offline-sale syncing are limited per till
  or person instead of per address.
- **Queries per scan grew with the cart.** Adding an item loaded every line's product one by one, and
  redrawing the cart did it again. Lines are now matched by id and the cart is redrawn from one
  preloaded query, so a scan costs the same 38 queries with 3 items in the cart or 30.
