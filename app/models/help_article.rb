# The help centre's articles. Each one's text is a partial in app/views/help/articles.
# They're listed in reading order: the help centre shows them section by section in this order, and each
# article's "Next" link goes to the one after it in its section.
class HelpArticle < Data.define(:slug, :title, :summary, :section, :related)
  SECTIONS = [ "Getting started", "At the till", "Customers and orders", "Stock and purchasing", "Money and tax", "Your account" ].freeze
  ARTICLES_PATH = Rails.root.join("app/views/help/articles")

  def self.all
    @all ||= [
      new("getting-started", "Setting up your shop", "The first afternoon: branches, taxes, products, staff and a test receipt.", "Getting started",
        %w[ importing-products staff-and-roles tills-and-printers ]),
      new("getting-around", "Finding your way around", "The six areas, Home, search, filtering lists, Group By, Settings and where Help is.", "Getting started",
        %w[ getting-started staff-and-roles ]),
      new("shop-settings", "Shop settings, branches and text messages", "Your shop's name, colours and logo, its preferences, branches and their receipt codes, tills, features, and texting customers.", "Getting started",
        %w[ tills-and-printers staff-and-roles getting-around ]),
      new("importing-products", "Importing products from a spreadsheet", "Bring in your whole price list at once, and update prices later the same way.", "Getting started",
        %w[ getting-started stock-and-stock-takes ]),
      new("staff-and-roles", "Staff, roles and PINs", "Who can do what, quick switching with a PIN, and approving discounts.", "Getting started",
        %w[ selling getting-started ]),
      new("tills-and-printers", "Tills, receipt printers and cash drawers", "Printing from the browser, or silently through QZ Tray, and opening the drawer.", "Getting started",
        %w[ selling offline ]),

      new("selling", "Selling at the till", "Opening a shift, scanning, discounts, parking a sale, taking payment, returns and closing up.", "At the till",
        %w[ tills-and-printers mpesa offline ]),
      new("shifts-and-cash", "Shifts, cash and closing up", "Opening with a float, cash drops and payouts, the X report, the blind count at close, over or short, and the Z report.", "At the till",
        %w[ selling reports foreign-currencies ]),
      new("returns-and-refunds", "Returns, refunds and voids", "Taking goods back against a receipt, restocking or writing off, refund methods, approval PINs, and voiding a sale rung up by mistake.", "At the till",
        %w[ selling staff-and-roles etims ]),
      new("offline", "When the internet goes down", "How the till keeps selling offline and sends the sales when it's back.", "At the till",
        %w[ selling tills-and-printers ]),
      new("whatsapp", "Sending documents: pictures, PDFs and WhatsApp", "Receipts, quotes, invoices and credit notes as pictures or PDFs to any app, and documents sent from your own WhatsApp with a link.", "At the till",
        %w[ selling customer-accounts ]),
      new("promotions", "Promotions and offers", "Percentages off, \"buy 10, get 1 free\" and mix-and-match bundles, applied by the till by itself.", "At the till",
        %w[ selling customer-accounts ]),

      new("customers", "Customers", "Adding customers with their KRA PIN and prices, choosing them at the till, and what the customer page shows.", "Customers and orders",
        %w[ customer-accounts contractor-jobs whatsapp ]),
      new("customer-accounts", "Customers on account, quotes and orders", "Credit limits, deposits, statements and delivery notes.", "Customers and orders",
        %w[ contractor-jobs mpesa reports ]),
      new("deliveries", "Deliveries and transport charges", "Charging transport at the till or afterwards, delivery notes, and tracking the lorry to site.", "Customers and orders",
        %w[ customer-accounts whatsapp ]),
      new("contractor-jobs", "Jobs for contractors", "Tag what contractors buy to their projects (online or offline), track it against a budget, and print a cost summary or a bill for their client.", "Customers and orders",
        %w[ customer-accounts ]),
      new("material-calculator", "The material calculator", "From a wall's, slab's or roof's measurements to the blocks, cement, steel and sheets it needs, and a quote at your prices.", "Customers and orders",
        %w[ customer-accounts products ]),
      new("fundis", "Fundi commissions", "Paying masons, plumbers and electricians a commission on the customers they bring: rates, naming them at the till, and paying them.", "Customers and orders",
        %w[ customers customer-accounts shifts-and-cash ]),
      new("online-store", "Selling online with click-and-collect", "Your catalogue online: switching it on, what customers see, and handling their orders.", "Customers and orders",
        %w[ customer-accounts mpesa ]),
      new("products", "Products and the catalogue", "Adding products, barcodes and pack sizes, loose goods, kits, special prices and quantity breaks, and printing shelf labels.", "Stock and purchasing",
        %w[ importing-products changing-prices stock-and-stock-takes ]),
      new("changing-prices", "Changing many prices at once", "Raising or lowering prices for a category, brand or supplier, with rounding and a preview.", "Stock and purchasing",
        %w[ importing-products stock-and-stock-takes ]),
      new("stock-and-stock-takes", "Stock levels, transfers and stock takes", "Adjusting stock, moving it between branches, counting it, and the reorder list.", "Stock and purchasing",
        %w[ stock-on-your-phone buying-from-suppliers batches-and-expiry ]),
      new("buying-from-suppliers", "Buying from suppliers", "Purchase orders, receiving deliveries, reorder suggestions, supplier invoices and what you owe.", "Stock and purchasing",
        %w[ supplier-returns stock-and-stock-takes foreign-currencies ]),
      new("stock-on-your-phone", "Stock on your phone", "Look up products, count stock takes and check deliveries in with your phone's camera.", "Stock and purchasing",
        %w[ stock-and-stock-takes buying-from-suppliers ]),
      new("batches-and-expiry", "Batches and expiry dates", "Selling the oldest first, writing off expired stock, counting by batch, and finding who bought a recalled batch.", "Stock and purchasing",
        %w[ stock-and-stock-takes buying-from-suppliers ]),
      new("supplier-returns", "Sending goods back to a supplier", "Damaged or wrong deliveries: taking them out of stock, the debit note, and the supplier's credit note.", "Stock and purchasing",
        %w[ buying-from-suppliers ]),

      new("mpesa", "M-Pesa payments", "Payment prompts to the customer's phone, and money paid straight to your Paybill or Till.", "Money and tax",
        %w[ airtel-money selling online-store reports ]),
      new("airtel-money", "Airtel Money", "Connecting your merchant account, prompts to the customer's phone, typed transaction IDs and late payments.", "Money and tax",
        %w[ mpesa selling reports ]),
      new("etims", "KRA eTIMS", "Connecting your branch's control unit and what happens when KRA is unreachable.", "Money and tax",
        %w[ selling offline reports ]),
      new("reports", "Reports and the owner's dashboard", "Today's takings at a glance, and sales, margin, VAT, stock and cash reports for any period.", "Money and tax",
        %w[ quickbooks selling buying-from-suppliers ]),
      new("quickbooks", "QuickBooks Online export", "A month of sales, payments and supplier bills as journal entries for your accountant to import.", "Money and tax",
        %w[ reports buying-from-suppliers ]),
      new("foreign-currencies", "Dollars and other currencies", "Taking foreign notes at the till, the daily market rate, counting them at close, and suppliers who invoice in dollars.", "Money and tax",
        %w[ selling buying-from-suppliers ]),

      new("my-profile", "Your profile and signing in", "Signing in at your shop's address, forgotten passwords, two-factor and recovery codes, PINs, Switch user and the daily email.", "Your account",
        %w[ staff-and-roles getting-around ]),
      new("billing", "Plans, billing and read-only mode", "Your free trial, paying HardPoint, changing plan and what happens if an invoice is late.", "Your account",
        %w[ your-data ]),
      new("connecting-apps", "Connecting a web shop or other apps", "API keys and webhooks, for the developer who connects your web shop or accounts.", "Your account",
        %w[ online-store billing ]),
      new("your-data", "Backups, exporting your data and closing your account", "Automatic and manual backups, downloading everything, and what happens when a shop is closed.", "Your account",
        %w[ billing ])
    ].freeze
  end

  def self.find(slug)
    all.find { _1.slug == slug.to_s } or raise ActiveRecord::RecordNotFound, "No help article #{slug}"
  end

  def self.in_section(section) = all.select { _1.section == section }

  # Articles whose title, summary or text mention every word of the query, best matches (in the title) first.
  def self.search(query)
    words = query.to_s.downcase.split
    return all if words.empty?

    all.select { |article| words.all? { article.searchable_text.include?(_1) } }
      .sort_by { |article| [ -words.count { article.title.downcase.include?(_1) }, all.index(article) ] }
  end

  def to_param = slug
  def partial = "help/articles/#{slug.underscore}"

  def related_articles = related.map { self.class.find(_1) }

  # The next article in reading order within the same section, if any.
  def next_article
    siblings = self.class.in_section(section)
    siblings[siblings.index(self) + 1]
  end

  # Articles are frozen, so the text is kept on the class.
  def searchable_text
    (self.class.instance_variable_get(:@searchable_texts) || self.class.instance_variable_set(:@searchable_texts, {}))[slug] ||=
      [ title, summary, section, body_text, *walkthrough_text ].join(" ").downcase
  end

  private
    # The steps of the walkthroughs shown in the article (config/help_tours.yml).
    def walkthrough_text
      HelpTour.for_article(slug).flat_map { |tour| [ tour.title, *tour.steps.flat_map { [ _1.title, _1.text ] } ] }
    end

    # The article's text without its markup, for searching. Links keep their wording.
    def body_text
      ARTICLES_PATH.join("_#{slug.underscore}.html.erb").read
        .gsub(/<%=\s*link_to\s+"([^"]*)".*?%>/m, ' \1 ')
        .gsub(/<%.*?%>/m, " ").gsub(/<[^>]+>/, " ").gsub(/&[a-z]+;/, " ").squish
    end
end
