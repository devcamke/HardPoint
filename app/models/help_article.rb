# The help centre's articles. Each one's text is a partial in app/views/help/articles.
class HelpArticle < Data.define(:slug, :title, :summary, :section)
  SECTIONS = [ "Getting started", "At the till", "Stock and purchasing", "Money and tax", "Your account" ].freeze

  def self.all
    @all ||= [
      new("getting-started", "Setting up your shop", "The first afternoon: branches, taxes, products, staff and a test receipt.", "Getting started"),
      new("importing-products", "Importing products from a spreadsheet", "Bring in your whole price list at once, and update prices later the same way.", "Getting started"),
      new("tills-and-printers", "Tills, receipt printers and cash drawers", "Printing from the browser, or silently through QZ Tray, and opening the drawer.", "Getting started"),
      new("staff-and-roles", "Staff, roles and PINs", "Who can do what, quick switching with a PIN, and approving discounts.", "Getting started"),
      new("selling", "Selling at the till", "Scanning, quantities, discounts, holding a sale, taking payment and returns.", "At the till"),
      new("offline", "When the internet goes down", "How the till keeps selling offline and sends the sales when it's back.", "At the till"),
      new("customer-accounts", "Customers on account, quotes and orders", "Credit limits, deposits, statements and delivery notes.", "At the till"),
      new("mpesa", "M-Pesa payments", "Payment prompts to the customer's phone, and money paid straight to your Paybill or Till.", "Money and tax"),
      new("etims", "KRA eTIMS", "Connecting your branch's control unit and what happens when KRA is unreachable.", "Money and tax"),
      new("online-store", "Selling online with click-and-collect", "Your catalogue online: switching it on, what customers see, and handling their orders.", "At the till"),
      new("foreign-currencies", "Dollars and other currencies", "Taking foreign notes at the till, counting them at close, and suppliers who invoice in dollars.", "Money and tax"),
      new("batches-and-expiry", "Batches and expiry dates", "Selling the oldest first, writing off expired stock, and finding who bought a recalled batch.", "Stock and purchasing"),
      new("stock-on-your-phone", "Stock on your phone", "Look up products, count stock takes and check deliveries in with your phone's camera.", "Stock and purchasing"),
      new("loyalty-points", "Loyalty points", "Customers earn points on what they buy and spend them at the till.", "At the till"),
      new("promotions", "Promotions and offers", "Percentages off and \"buy 10, get 1 free\", applied by the till by itself.", "At the till"),
      new("contractor-jobs", "Jobs for contractors", "Tag what contractors buy to their projects, track it against a budget and print a cost summary.", "At the till"),
      new("tool-hire", "Hiring out tools", "Tools for hire, hire agreements, deposits, returns and settling up at the till.", "At the till"),
      new("connecting-apps", "Connecting a web shop or other apps", "API keys and webhooks, for the developer who connects your web shop or accounts.", "Your account"),
      new("billing", "Plans, billing and read-only mode", "Your free trial, paying HardPoint, changing plan and what happens if an invoice is late.", "Your account"),
      new("your-data", "Exporting your data and closing your account", "Download everything, and what happens when a shop is closed.", "Your account")
    ].freeze
  end

  def self.find(slug)
    all.find { _1.slug == slug.to_s } or raise ActiveRecord::RecordNotFound, "No help article #{slug}"
  end

  def self.in_section(section) = all.select { _1.section == section }

  def to_param = slug
  def partial = "help/articles/#{slug.underscore}"
end
