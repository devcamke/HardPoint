# The Settings page: each setting as a card with an icon, what it's for, and how it's set now, grouped by what it's
# about. Cards a role can't use, and features a shop hasn't switched on, are left out.
module SettingsHelper
  SettingsCard = Data.define(:name, :path, :description, :icon, :status, :keywords)

  SETTINGS_ICONS = {
    shop: "M3 9l1.5-5h15L21 9M3 9h18M4 9v11h16V9M9 20v-6h6v6",
    palette: "M12 3a9 9 0 1 0 0 18c1 0 1.5-.7 1.5-1.5 0-1.1-1-1.4-1-2.5 0-.9.7-1.5 1.7-1.5H17a4 4 0 0 0 4-4c0-4.7-4-8.5-9-8.5ZM7.5 11.5h.01M9.5 7.5h.01M14.5 7.5h.01",
    sliders: "M4 6h9M17 6h3M4 12h3M11 12h9M4 18h11M19 18h1M15 4v4M9 10v4M17 16v4",
    toggle: "M7 7h10a5 5 0 0 1 0 10H7A5 5 0 0 1 7 7ZM16 12h.01",
    card: "M3 6h18v12H3zM3 10h18M7 15h3",
    checklist: "M10 6h10M10 12h10M10 18h10M4 6l1.5 1.5L8 5M4 12l1.5 1.5L8 11M4 18l1.5 1.5L8 17",
    database: "M4 6c0-1.7 3.6-3 8-3s8 1.3 8 3-3.6 3-8 3-8-1.3-8-3Zm0 0v12c0 1.7 3.6 3 8 3s8-1.3 8-3V6M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3",
    pin: "M12 21s-7-6.2-7-11a7 7 0 0 1 14 0c0 4.8-7 11-7 11ZM12 10h.01",
    till: "M4 4h16v10H4zM2 18h20v2H2zM7 7h10M7 10h6",
    people: "M16 20v-1a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v1M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8ZM22 20v-1a4 4 0 0 0-3-3.9M16 3.1a4 4 0 0 1 0 7.8",
    clock: "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18ZM12 7v5l3 2",
    bell: "M6 16v-5a6 6 0 1 1 12 0v5l2 2H4l2-2ZM10 20a2 2 0 0 0 4 0",
    mail: "M3 6h18v12H3zM3 7l9 6 9-6",
    tag: "M3 12V4h8l10 10-8 8-10-10ZM7.5 8h.01",
    hammer: "M14.5 5.5 18.5 9.5M3 21l9.5-9.5M11 4l4-2 7 7-2 4-9-9Z",
    calculator: "M6 3h12v18H6zM9 7h6M9 11h.01M12 11h.01M15 11h.01M9 14h.01M12 14h.01M15 14h.01M9 17h.01M12 17h3",
    globe: "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18ZM3 12h18M12 3c2.5 2.5 3.5 5.5 3.5 9s-1 6.5-3.5 9c-2.5-2.5-3.5-5.5-3.5-9S9.5 5.5 12 3Z",
    phone: "M8 2h8v20H8zM11 18h2",
    receipt: "M6 2h12v20l-3-2-3 2-3-2-3 2V2ZM9 7h6M9 11h6M9 15h4",
    message: "M4 4h16v12H8l-4 4V4Z",
    money: "M12 2v20M17 6H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6",
    percent: "M19 5 5 19M7 5a2 2 0 1 0 0 4 2 2 0 0 0 0-4ZM17 15a2 2 0 1 0 0 4 2 2 0 0 0 0-4Z",
    folder: "M3 6h6l2 2h10v11H3z",
    star: "M12 3l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.4 6.8 19.1l1-5.8-4.3-4.1 5.9-.9L12 3Z",
    ruler: "M3 17 17 3l4 4L7 21ZM7 13l2 2M10 10l2 2M13 7l2 2",
    upload: "M12 16V4M7 9l5-5 5 5M4 20h16",
    code: "M8 7l-5 5 5 5M16 7l5 5-5 5"
  }.freeze

  def settings_icon(name, **options)
    tag.svg(tag.path(d: SETTINGS_ICONS.fetch(name)), viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", "stroke-width": 1.8,
      "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": "true", **options)
  end

  # { "Your shop" => [ SettingsCard, … ], … }, empty groups left out. The keys stay as the guided tour knows them.
  def settings_sections
    account, m = Current.account, current_membership
    card = ->(name, path, description, icon, status = nil, keywords = "") { SettingsCard.new(name, path, description, icon, status, keywords) }
    owner = m.can_manage_account?

    {
      "Your shop" => [
        (card.("Shop details", edit_account_path, "Name, time zone, currency, the receipt footer, discount and payout limits", :shop,
          "#{account.time_zone} · #{account.currency}", "name timezone currency receipt footer discount payout two-factor 2fa") if owner),
        (card.("Appearance", edit_appearance_path, "Your colour theme, your logo, and the receipt stamp", :palette,
          settings_swatch(account), "colour color theme logo brand stamp look") if owner),
        (card.("Shop preferences", edit_preferences_path, "Quotes, the till's payment buttons, stock warnings, what quotes and invoices say", :sliders,
          "Quotes valid #{account.quote_validity_days} days · #{1 + account.till_tenders.size} payment buttons", "quote validity terms payment buttons tenders expiry dead stock reorder lead time bank paybill") if owner),
        (card.("Features", features_path, "Switch on only what your shop uses", :toggle,
          "#{account.features.size} of #{Account::Features::KEYS.size} switched on", "jobs batches serial promotions currencies deliveries fundis online api") if owner),
        card.("Branches", branches_path, "Your locations, their addresses and receipt codes", :pin, pluralize(account.branches.count, "branch")),
        card.("Tills", registers_path, "Points of sale in each branch, and their printers", :till, pluralize(account.registers.count, "till"), "register printer"),
        (card.("Billing", billing_path, "Your HardPoint plan, invoices and payments", :card,
          "#{Plan.find(account.plan)&.name || account.plan.humanize} · #{account.subscription_status.humanize}", "plan subscription invoice pay") if owner),
        (card.("Set up your shop", onboarding_path, "The first-day checklist", :checklist,
          account.onboarding_completed_at ? status_dot("Done", :success) : status_dot("Not finished", :warning)) if owner),
        (card.("Your data", account_data_path, "Backups, export everything, or close the account", :database,
          "Backed up #{account.backup_frequency.humanize.downcase}", "backup export delete close") if m.owner?)
      ],
      "People" => [
        (card.("Staff", memberships_path, "Who can sign in, their roles and till PINs", :people, pluralize(account.memberships.count, "person", plural: "people"), "users roles pin cashier manager") if m.can_manage_staff?),
        (card.("Activity", events_path, "Who did what, and when", :clock, nil, "log audit history") if m.can_manage_staff?),
        (card.("Alerts", edit_account_path(anchor: "alerts"), "Emails straight away when a till closes short, a big sale is voided or a count loses stock", :bell,
          "Short over #{Money.format(account.alert_shift_short_above_cents, currency: account.currency)}", "alert email void short count") if owner),
        (card.("Your emails", my_profile_path, "The daily and weekly summaries and alerts you get", :mail,
          "#{[ m.daily_summary?, m.weekly_summary?, (m.alert_emails? if m.approver?) ].compact.count(true)} switched on", "summary daily weekly email") if m.can_view_reports?)
      ],
      "Selling" => [
        card.("Price lists", price_lists_path, "Contractor and wholesale prices", :tag, pluralize(account.price_lists.count, "price list"), "wholesale contractor"),
        (card.("Fundi commissions", edit_fundi_rates_path, "What fundis earn on the customers they bring", :hammer,
          "#{plain_number(account.fundi_commission_percent)}% shop rate", "fundi commission mason plumber") if account.feature?(:fundis) && m.approver?),
        (card.("Material calculator", edit_material_products_path, "Which of your products is each material", :calculator,
          "#{account.material_products.count} of #{MaterialCalculator::MATERIALS.size} materials linked", "calculator materials cement sand quote") if m.can_manage_catalogue?),
        (card.("Online store", edit_storefront_path, "Sell online for collection at your branches", :globe,
          account.storefront&.enabled? ? status_dot("Open", :success) : status_dot("Closed", :muted), "web shop click collect") if owner && account.feature?(:online_store))
      ],
      "Payments and tax" => [
        (card.("M-Pesa", mpesa_shortcodes_path, "Paybill or Till: prompts to pay from the till, payments received", :phone,
          connected(account.mpesa_shortcodes.active.count), "mpesa safaricom paybill till stk") if owner),
        (card.("Airtel Money", airtel_merchants_path, "Prompts to pay with Airtel Money from the till", :phone, connected(account.airtel_merchants.count), "airtel") if owner),
        (card.("KRA eTIMS", etims_devices_path, "Send sales to KRA and print signed receipts", :receipt, connected(account.etims_devices.active.count), "kra etims tax tims") if owner),
        (card.("SMS", edit_account_path(anchor: "sms"), "Text receipts, order updates and balance reminders", :message,
          account.sms_enabled? ? status_dot("On", :success) : status_dot("Off", :muted), "text sms") if owner),
        (card.("Currencies", currencies_path, "Dollars at the till, suppliers who invoice in them, and today's rates", :money,
          pluralize(account.currencies.count, "currency", plural: "currencies"), "dollar usd exchange") if account.feature?(:currencies) && m.approver?),
        card.("Tax rates", tax_rates_path, "VAT and other rates", :percent, pluralize(account.tax_rates.count, "rate"), "vat tax")
      ],
      "Catalogue" => [
        card.("Categories", categories_path, "Group products, e.g. Plumbing › Pipes", :folder, pluralize(account.categories.count, "category", plural: "categories")),
        card.("Brands", brands_path, "Makers and suppliers' brands", :star, pluralize(account.brands.count, "brand")),
        card.("Units", units_path, "Piece, bag, kilogram, metre…", :ruler, pluralize(account.units.count, "unit")),
        (card.("Import products", product_imports_path, "Load or update products from a spreadsheet", :upload, nil, "csv excel spreadsheet") if m.can_manage_catalogue?)
      ],
      "Connections" => [
        (card.("Developers", developers_path, "API keys and webhooks for web shops and other apps", :code,
          pluralize(account.api_keys.active.count, "active key"), "api webhook integration") if owner && account.feature?(:developers))
      ]
    }.transform_values(&:compact).compact_blank
  end

  private
    def settings_swatch(account)
      preset = Theme::PRESETS.values.find { _1.color == account.theme_color }
      safe_join([ tag.span(class: "inline-block size-3 rounded-sm align-middle", style: "background: #{account.theme_color}"),
                  " #{preset&.name || "Your own colour"}#{" · logo" if account.logo.attached?}" ])
    end

    def connected(count)
      count.positive? ? status_dot(count == 1 ? "Connected" : "#{count} connected", :success) : status_dot("Not set up", :muted)
    end
end
