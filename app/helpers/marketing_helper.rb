# The public site's questions and answers, shown on the pricing page in full and on the landing page in part,
# and given to search engines as FAQ structured data on both.
module MarketingHelper
  def marketing_faqs
    [
      [ "What happens after the free trial?", "We email your first invoice when the trial ends. You have a week to pay it by M-Pesa or card from the Billing page, and we remind you before it's due." ],
      [ "What if an invoice isn't paid?", "After the week's grace the shop becomes read-only: you and your staff can still sign in, look up anything and export your data, but can't sell or change things until it's paid. Nothing is deleted." ],
      [ "Can I change plan?", "Yes, whenever you like, from the Billing page. A bigger plan applies at once; a smaller one if what you use fits it. The new price applies from the next invoice." ],
      [ "What counts towards the limits?", "Branches, active tills and staff logins. Retired tills don't count, and products never do: every plan takes as many as you stock." ],
      [ "What if I need one more till or branch?", "Add it from the Billing page for a small monthly amount instead of moving up a plan. The extra applies straight away and is on your next invoice." ],
      [ "Is it cheaper to pay for a year?", "Yes. Choose yearly billing on the Billing page and each invoice covers twelve months for the price of #{Plan::YEARLY_MONTHS_CHARGED}." ],
      [ "Can you set the shop up for us?", "Yes. Our setup and training visit imports your product list, connects your printers, scanner, M-Pesa and KRA eTIMS, and trains your staff at the counter. It's from KES #{number_with_delimiter(Plan::SETUP_CENTS / 100)}, and free when you pay a year upfront." ],
      [ "Is my shop's data safe?", "Yes. Each shop's data is separated inside the database itself, connections and backups are encrypted, backups run every minute to a second place, and owners and managers can turn on two-factor sign-in. We never sell data or show adverts. The privacy page and data processing terms have the details." ],
      [ "Can I bring my products from my old system?", "Yes. Save your price list as a spreadsheet (CSV) and import it: products, prices, barcodes and the stock on the shelf, thousands in seconds. HardPoint checks the whole file first and lists any problem by line. Or we import it for you on a setup visit." ],
      [ "Can I bring my customers and what they owe me?", "Yes. Import your customers from a spreadsheet with each one's balance, and it goes on their account as an opening balance: it shows on their statement and in who owes what, and their payments settle it first. It isn't counted as a sale, so it stays out of your takings and VAT. Suppliers come across the same way, with what you owe each one." ],
      [ "Can I take my data with me?", "Always. Export everything as spreadsheets (CSV) from Settings, whether or not you're paying, and close your account whenever you want." ],
      [ "Is there an uptime guarantee?", "Yes, for Business and Unlimited: 99.9% a month, with a credit on your next invoice if we miss it, and a 2-hour (Business) or 1-hour (Unlimited) response when a till can't sell. It's all written down in the service level agreement. Whatever the plan, the till keeps selling when the internet is down." ],
      [ "Do I need special hardware?", "No. HardPoint runs in the browser on any computer or tablet. USB barcode scanners work as they are, and receipts print on 58 mm or 80 mm thermal printers. If you'd rather have it all arrive ready to plug in, we quote a till kit: printer, cash drawer, scanner and, if you want one, a touch screen." ]
    ]
  end

  # The questions a visitor has before clicking Start, for the landing page.
  # What real shops say, from config/testimonials.yml: quote, name, shop and town, with an optional role and photo.
  # Entries missing any of the four are left out rather than shown half-filled.
  def testimonials
    path = Rails.root.join("config/testimonials.yml")
    entries = path.exist? ? YAML.safe_load_file(path) : nil
    Array(entries).filter_map do |entry|
      entry = entry.to_h.symbolize_keys.slice(:quote, :name, :role, :shop, :town, :photo)
      entry if entry.values_at(:quote, :name, :shop, :town).all?(&:present?)
    end
  end

  # The film behind the landing page's "Watch a sale": app/assets/images/marketing/sale.mp4, or sale.webm, with an
  # optional still beside it, sale-poster.jpg. Today it's a screen recording of a sale in the demo shop, made by
  # script/sale_video.mjs; a film of a real counter saved as sale.mp4 takes its place. With no file the dialog shows
  # the walkthrough alone.
  def sale_video
    directory = Rails.root.join("app/assets/images/marketing")
    file = %w[ sale.mp4 sale.webm ].find { directory.join(_1).exist? } or return
    { src: "marketing/#{file}", recording: file.end_with?(".webm"), poster: ("marketing/sale-poster.jpg" if directory.join("sale-poster.jpg").exist?) }
  end

  def landing_faqs
    wanted = [ "What happens after the free trial?", "Do I need special hardware?", "Can you set the shop up for us?",
               "What if I need one more till or branch?", "Is my shop's data safe?", "Can I take my data with me?" ]
    marketing_faqs.select { |question, _| wanted.include?(question) }.sort_by { |question, _| wanted.index(question) }
  end
end
