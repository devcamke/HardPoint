# The public site's pages about one job HardPoint does (KRA eTIMS, M-Pesa, selling offline) or one market (East
# Africa), for people searching for exactly that. Each says only what HardPoint does today; the help guides it
# links to have the detail. Kept here, like HelpArticle, so the page, the sitemap and llms.txt read the same list.
class SolutionPage < Data.define(:slug, :title, :description, :heading, :intro, :sections, :faqs, :help)
  Section = Data.define(:heading, :points)

  def self.all
    @all ||= [
      new("kra-etims-pos",
        "KRA eTIMS POS for hardware stores in Kenya",
        "A point of sale that sends every sale to KRA eTIMS and prints KRA's QR code on the receipt. Sales keep going when KRA is down, and are sent when it's back. Built for Kenyan hardware stores.",
        "Every sale sent to KRA eTIMS, without slowing the counter.",
        "HardPoint signs each sale with KRA's eTIMS as it's made, prints KRA's QR code on the receipt, and sends voids and returns as credit notes. When KRA can't be reached the till keeps selling and sends the sales later.",
        [ Section.new("How it works", [
            "One OSCU control unit per branch, registered on KRA's eTIMS portal and set up in HardPoint with your PIN, branch ID and serial number.",
            "Products are registered with KRA the first time they're sold at a branch, and again when a product's name or tax rate changes.",
            "Every sale is sent and signed; the receipt carries KRA's signature and QR code.",
            "Voids and returns go to KRA as credit notes against the original sale." ]),
          Section.new("When KRA is slow or down", [
            "The sale goes ahead and joins a queue. HardPoint keeps retrying, with growing gaps, in order for each control unit.",
            "Every hour HardPoint looks for any sale that never reached the queue and sends it.",
            "Anything KRA refuses is listed with KRA's reason, to fix and send again, and the owner's dashboard warns about it." ]),
          Section.new("Tax done right", [
            "Standard-rated, zero-rated and exempt goods are kept apart on every sale line, so the VAT report and eTIMS agree.",
            "A customer's KRA PIN is checked and printed on their invoice.",
            "Sales rung up while the till was offline are sent to KRA as soon as they reach HardPoint." ]) ],
        [ [ "Do I need a separate eTIMS device?", "No hardware. eTIMS OSCU is an online control unit: you register it for each branch on KRA's eTIMS portal and HardPoint talks to it." ],
          [ "What happens if KRA's system is down?", "The till keeps selling. Sales are queued and sent when KRA answers, oldest first, and you can see anything still waiting in Settings › KRA eTIMS." ],
          [ "Can you set eTIMS up for us?", "Yes. The setup and training visit includes registering eTIMS for each branch, and it's free with a year paid upfront." ] ],
        %w[ etims reports ]),

      new("mpesa-pos",
        "M-Pesa and Airtel Money POS for hardware stores",
        "Take M-Pesa and Airtel Money at the till on your own Paybill or Till number: payment prompts to the customer's phone, payments made straight to your Paybill matched automatically, and a reconciliation report.",
        "M-Pesa and Airtel Money at the counter, matched to the sale by themselves.",
        "Connect your own Paybill or Till number and your Airtel Money merchant account. The cashier sends a prompt to the customer's phone, the customer enters their PIN, and the sale completes itself when the money arrives.",
        [ Section.new("At the till", [
            "Payment prompts (STK push) to the customer's phone for the exact amount, for M-Pesa and Airtel Money.",
            "Money paid straight to your Paybill or Till by Lipa na M-Pesa shows up at the till within seconds, ready to use on a sale.",
            "A transaction code typed by the cashier claims the matching payment.",
            "Split a sale across cash, M-Pesa, card and the customer's account." ]),
          Section.new("Matched without the paperwork", [
            "A payment with an order number as the account becomes a deposit on that order; one with a customer's account number pays their account.",
            "The M-Pesa reconciliation report shows money received but not used, and codes typed at a till that Safaricom never confirmed.",
            "Customers who pay too much get the change recorded; nothing is lost when a customer walks away mid-prompt." ]),
          Section.new("Your money, your account", [
            "Payments go straight to your own Paybill, Till or Airtel merchant account. HardPoint never holds your money.",
            "Your Daraja and Airtel API keys are stored encrypted.",
            "Balance reminders by SMS carry your Paybill, so customers on account can pay from their phone." ]) ],
        [ [ "Do I need a new Paybill?", "No. HardPoint uses your existing Paybill or Till number through Safaricom's Daraja API." ],
          [ "Does HardPoint take a cut of M-Pesa payments?", "No. Customers pay you directly; Safaricom's and Airtel's usual charges apply, and HardPoint's plan price covers the rest." ],
          [ "What if the internet is down?", "The offline till still takes M-Pesa: the cashier types the transaction code, and it's checked against Safaricom's records when the till is back online." ] ],
        %w[ mpesa airtel-money ]),

      new("offline-pos",
        "Offline POS: keep selling when the internet drops",
        "HardPoint's till keeps selling when the internet drops out: scan, take cash or M-Pesa codes and print receipts, then every sale is sent once the connection is back.",
        "The internet drops. The till doesn't.",
        "Each till keeps an offline copy of itself and your catalogue. When the connection goes, it switches to the offline till: keep scanning, take cash or a typed M-Pesa code, and print a receipt. Every sale is sent, once, when the connection is back.",
        [ Section.new("Selling offline", [
            "Scan or search products at the prices, packs and quantity breaks the till had when it was last online.",
            "Cash with change, typed M-Pesa, Airtel Money and card codes, and customers' own prices.",
            "Offline receipts carry their own numbers, so they never clash with another till or device.",
            "A connection light on every till page shows Online or Offline and how many sales are waiting." ]),
          Section.new("Back online", [
            "Waiting sales go up by themselves, each recorded once however many times the connection comes and goes.",
            "Each sale keeps the time it really happened, gets its real receipt number, and is sent to KRA eTIMS.",
            "Anything worth a second look, like a price that has since gone up or stock now below zero, is flagged for a manager." ]) ],
        [ [ "How long can the till stay offline?", "As long as it needs to. Sales wait on that computer until the connection is back. Open the till once a day while online so its prices are fresh." ],
          [ "Does it need special software?", "No. It's the same HardPoint in a web browser, installed on the till so it opens even with no connection." ] ],
        %w[ offline tills-and-printers ]),

      new("east-africa",
        "Hardware store POS for East Africa",
        "HardPoint is built in Kenya for Kenyan hardware stores, and handles the trade that crosses East Africa's borders: Ugandan and Tanzanian shillings and dollars at the till, and suppliers who invoice in dollars.",
        "Built in Kenya, for trade that crosses borders.",
        "HardPoint keeps your books in Kenya shillings with M-Pesa, Airtel Money and KRA eTIMS. Shops in Busia, Malaba, Namanga, Isebania, Taveta and Lunga Lunga also take Ugandan and Tanzanian shillings and dollars at the till, and buy from importers who invoice in dollars.",
        [ Section.new("Other currencies at the till", [
            "Take Ugandan shillings, Tanzanian shillings, dollars or any other currency as a payment; the till shows what the notes are worth and gives change in Kenya shillings.",
            "Rates follow the daily market rate less a margin you choose, or are set by hand, and a sudden jump waits for a manager.",
            "The drawer is counted per currency at close, and the receipt shows the notes and the rate." ]),
          Section.new("Buying from abroad", [
            "Suppliers who invoice in dollars keep their orders, invoices, payments and balance in dollars.",
            "Goods are costed in shillings at the day's rate, with transport and duty added, so margins stay true.",
            "Each payment and invoice keeps the rate it used, so a new rate never rewrites history." ]),
          Section.new("Outside Kenya", [
            "HardPoint works for selling, stock, customers and suppliers wherever a shop is, in a web browser.",
            "Mobile money and tax filing are Kenyan today: M-Pesa, Airtel Money Kenya and KRA eTIMS. HardPoint doesn't yet send sales to URA's EFRIS, TRA or RRA.",
            "Running a hardware store in Uganda, Tanzania or Rwanda? Message us: it tells us where to go next." ]) ],
        [ [ "Can I use HardPoint in Uganda or Tanzania?", "You can sell, keep stock and run customer accounts, but local tax systems (EFRIS, TRA's VFD) and local mobile money aren't connected yet, so ask us before you start." ],
          [ "Can my Kenyan shop take Ugandan or Tanzanian shillings?", "Yes. Switch on Foreign currencies, add the rates, and the till takes them as a payment with change in Kenya shillings." ] ],
        %w[ foreign-currencies buying-from-suppliers ])
    ].freeze
  end

  def self.slugs = all.map(&:slug)

  def self.find(slug)
    all.find { _1.slug == slug } or raise ActiveRecord::RecordNotFound, "No page #{slug}"
  end

  def to_param = slug

  # For the footer, where the full titles are too long.
  def label
    { "kra-etims-pos" => "KRA eTIMS POS", "mpesa-pos" => "M-Pesa POS", "offline-pos" => "Offline POS", "east-africa" => "East Africa" }.fetch(slug)
  end

  def help_articles
    help.filter_map { |slug| HelpArticle.all.find { _1.slug == slug } }
  end
end
