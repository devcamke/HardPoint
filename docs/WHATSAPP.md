# WhatsApp from HardPoint

Shops with **WhatsApp from HardPoint** switched on (Settings › Features) send receipts, quotes and orders, credit
notes, statements and balance reminders from HardPoint's own WhatsApp number, with the document attached and the
shop's name in the message, and see when each is delivered and read. It runs on Meta's **WhatsApp Cloud API**.

Until the number is connected, the feature runs in **test mode** outside production: messages are recorded on
Settings › WhatsApp messages and marked "Test mode", and nothing leaves the server. On a live server without the
keys it's **off**: nothing can be sent and the page says the number is being set up. The share menu's *Share as a
picture* and the WhatsApp button (from the person's own phone) work either way.

## Setting it up

1. **Meta Business account** for HardPoint, verified, with a **WhatsApp Business Account** and a phone number of its own
   (not one in use on a phone). Display name: *HardPoint*.
2. **A system user** in Meta Business Settings with a permanent access token that has `whatsapp_business_messaging`
   on that WhatsApp Business Account.
3. **The two templates below**, submitted for approval in WhatsApp Manager, category **Utility**, language
   **English (en)**, each with a **Document** header. Names and placeholders must match exactly.
4. **The webhook**: in the Meta app's WhatsApp › Configuration, callback URL `https://<APP_HOST>/webhooks/whatsapp`,
   a verify token of our choosing, subscribed to **messages** (which carries the status updates).
5. **The keys** in the production environment (Kamal secrets), then deploy:

| Variable | What it is |
|---|---|
| `WHATSAPP_PHONE_NUMBER_ID` | The phone number's id (WhatsApp Manager › Phone numbers), not the number itself |
| `WHATSAPP_ACCESS_TOKEN` | The system user's permanent token |
| `WHATSAPP_APP_SECRET` | The Meta app's secret: status updates are checked against it (`X-Hub-Signature-256`) |
| `WHATSAPP_VERIFY_TOKEN` | The verify token typed into the webhook configuration |
| `WHATSAPP_GRAPH_VERSION` | Optional, default `v21.0` |

With `WHATSAPP_PHONE_NUMBER_ID` and `WHATSAPP_ACCESS_TOKEN` set, messages go to Meta for real.

## Templates

**`hardpoint_document`** — Document header (the PDF HardPoint attaches). Body:

> {{1}} has sent you {{2}} {{3}} for {{4}}. Reply to {{1}} with any questions.

Example: *Demo Hardware* has sent you *your receipt* *MAI-000220* for *KES 15,000.00*.

| | Filled with |
|---|---|
| {{1}} | the shop's name |
| {{2}} | "your receipt", "a quote", "your order", "a credit note", "your statement" |
| {{3}} | the receipt, quote, order or credit note number, or the statement's period |
| {{4}} | the amount (for a statement, its balance) |

**`hardpoint_balance_reminder`** — Document header (the customer's statement). Body:

> {{1}}: hello {{2}}, your account shows {{3}} owed, {{4}} of it overdue. Your statement is attached.

| | Filled with |
|---|---|
| {{1}} | the shop's name |
| {{2}} | the customer's name |
| {{3}} | the balance |
| {{4}} | the overdue part |

The PDF reaches Meta as a share link (`/share/<token>.pdf`, 30 days, revocable from the document's page), the same
kind of link the WhatsApp button sends.

## Cost

Meta charges per conversation (Utility rates for Kenya). Decide before launch whether it's inside the plan price, a
monthly allowance, or billed to the shop. Every message is a row in `whatsapp_messages`, per shop, to count from.

## What's recorded

`Whatsapp::Message`: the template, the number (as WhatsApp wants it, `2547…`), the customer's name, who sent it, the
document and its share link, Meta's message id, and its status: **queued** → **sent** → **delivered** → **read**, or
**failed** with Meta's reason, or **simulated** in test mode. Statuses only move forward, so a late "sent" never
undoes "read". Sending is a job (`Whatsapp::DeliveryJob`) that retries while Meta can't be reached.
