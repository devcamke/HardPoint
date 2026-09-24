# Development data. Shops live on subdomains of localhost (browsers resolve *.localhost):
#   http://demo.localhost:3000   owner@demo.test / hardpoint-demo   (cashier PIN: Carol 1234)
#   http://admin.localhost:3000  admin@hardpoint.test / hardpoint-demo, two-factor key below
if Rails.env.development? && !Account.exists?(subdomain: "demo")
  DEV_ADMIN_TWO_FACTOR_SECRET = "HARDPOINTDEVADMINTOTPSECRETKEYAB" # add to an authenticator app for local use only

  Signup.new(shop_name: "Demo Hardware", subdomain: "demo", owner_name: "Wanjiru Kamau",
    email_address: "owner@demo.test", password: "hardpoint-demo").save!

  account = Account.find_by!(subdomain: "demo")
  owner = User.find_by!(email_address: "owner@demo.test")

  Current.account = account
  Current.session = account.sessions.create!(user: owner)

  begin
    main = account.branches.find_by!(name: "Main branch")
    main.update!(name: "Moi Avenue", address: "Moi Avenue, Nairobi", phone: "+254 700 000 001")
    yard = account.branches.create!(name: "Industrial Area yard", address: "Enterprise Road, Nairobi")

    account.registers.create!(branch: main, name: "Front counter")
    account.registers.create!(branch: main, name: "Paint & tools desk")
    account.registers.create!(branch: yard, name: "Yard gate")

    account.memberships.create!(role: :manager, user_attributes: { name: "Otieno Manager", email_address: "manager@demo.test" })
    account.memberships.create!(role: :cashier, user_attributes: { name: "Carol Cashier", email_address: "cashier@demo.test" }).set_pin("1234")
    account.memberships.create!(role: :stock_clerk, user_attributes: { name: "Juma Stock", email_address: "stock@demo.test" }).set_pin("5678")

    # A small hardware catalogue: name, SKU, category, brand, unit, price, cost, reorder level, stock at Moi Avenue, stock at the yard.
    # Prices include VAT; costs are listed as invoiced (with VAT) and stored without it, as a VAT-registered shop records them.
    ex_vat = ->(amount) { (amount / 1.16).round(2) }
    unit = ->(name) { account.units.find_by!(name: name) }
    catalogue = [
      [ "Portland cement 50kg", "CEM-BAM-50", "Building materials", "Bamburi", "Bag", 850, 740, 40, 180, 420 ],
      [ "Portland cement 50kg (Savannah)", "CEM-SAV-50", "Building materials", "Savannah", "Bag", 800, 700, 40, 26, 300 ],
      [ "River sand (per tonne)", "SAND-T", "Building materials", nil, "Kilogram", 3.2, 2.1, 0, 0, 18000 ],
      [ "Y12 deformed bar 12m", "STL-Y12", "Steel", "Devki", "Length", 1150, 980, 50, 64, 520 ],
      [ "Y10 deformed bar 12m", "STL-Y10", "Steel", "Devki", "Length", 820, 700, 50, 12, 380 ],
      [ "BRC mesh A142", "STL-BRC142", "Steel", "Devki", "Sheet", 6800, 5900, 10, 8, 45 ],
      [ "Binding wire 25kg", "STL-BW25", "Steel", nil, "Roll", 4300, 3700, 5, 14, 20 ],
      [ "Iron sheet gauge 30 3m (maroon)", "ROOF-G30-3M", "Roofing", "Mabati Rolling Mills", "Sheet", 1450, 1220, 30, 95, 160 ],
      [ "Ridge cap gauge 30 (maroon)", "ROOF-RIDGE", "Roofing", "Mabati Rolling Mills", "Piece", 650, 520, 10, 22, 30 ],
      [ "Roofing nails 3 inch", "NAIL-ROOF", "Fasteners", nil, "Kilogram", 300, 210, 10, 36.5, 80 ],
      [ "Wire nails 4 inch", "NAIL-4", "Fasteners", nil, "Kilogram", 250, 175, 10, 42, 60 ],
      [ "Wood screws 8 x 1.5 inch", "SCR-815", "Fasteners", "Spax", "Piece", 5, 3, 500, 2400, 0 ],
      [ "PVC pipe 2 inch 6m", "PVC-2", "Plumbing", "Kentube", "Piece", 1200, 900, 10, 4, 25 ],
      [ "PVC pipe 4 inch 6m", "PVC-4", "Plumbing", "Kentube", "Piece", 2450, 1900, 6, 11, 18 ],
      [ "PPR pipe 20mm 4m", "PPR-20", "Plumbing", "Kentube", "Piece", 380, 260, 20, 55, 40 ],
      [ "Brass gate valve 3/4", "PLB-GV34", "Plumbing", "Pegler", "Piece", 1350, 980, 5, 9, 0 ],
      [ "Garden tap brass 1/2", "PLB-TAP12", "Plumbing", "Pegler", "Piece", 950, 640, 8, 3, 0 ],
      [ "Crown emulsion white 20l", "PNT-CRN-W20", "Paint", "Crown", "Tin", 8900, 7600, 5, 12, 0 ],
      [ "Crown gloss black 4l", "PNT-CRN-B4", "Paint", "Crown", "Tin", 3100, 2550, 5, 7, 0 ],
      [ "Paint brush 3 inch", "PNT-BR3", "Paint", nil, "Piece", 280, 150, 20, 64, 0 ],
      [ "Twin & earth cable 2.5mm 100m", "ELC-TE25", "Electrical", "East African Cables", "Roll", 9800, 8300, 3, 6, 2 ],
      [ "Switch 1-gang", "ELC-SW1", "Electrical", "Tronic", "Piece", 180, 110, 30, 140, 0 ],
      [ "LED bulb 9W B22", "ELC-LED9", "Electrical", "Philips", "Piece", 250, 160, 40, 18, 0 ],
      [ "Claw hammer 16oz", "TL-HAM16", "Hand tools", "Stanley", "Piece", 1300, 900, 5, 17, 0 ],
      [ "Tape measure 5m", "TL-TAPE5", "Hand tools", "Stanley", "Piece", 650, 430, 10, 32, 0 ],
      [ "Spirit level 600mm", "TL-LVL600", "Hand tools", "Stanley", "Piece", 1450, 1050, 4, 6, 0 ],
      [ "Angle grinder 115mm 750W", "PT-AG115", "Power tools", "Makita", "Piece", 7900, 6200, 2, 4, 0 ],
      [ "Impact drill 13mm 710W", "PT-DR13", "Power tools", "Bosch", "Piece", 9800, 7700, 2, 1, 0 ],
      [ "Wheelbarrow heavy duty", "TL-WB", "Hand tools", "Tanga", "Piece", 5600, 4500, 3, 8, 6 ],
      [ "Padlock 50mm", "SEC-PL50", "Security", "Union", "Piece", 890, 560, 10, 25, 0 ]
    ]

    main, yard = account.branches.alphabetically.to_a.values_at(1, 0)
    catalogue.each do |name, sku, category, brand, unit_name, price, cost, reorder, main_stock, yard_stock|
      product = account.products.create!(name: name, sku: sku, unit: unit.(unit_name), price: price, cost: ex_vat.(cost), reorder_level: reorder,
        category: account.categories.find_or_create_by!(name: category), brand: brand && account.brands.find_or_create_by!(name: brand),
        tax_rate: account.default_tax_rate, serialized: category == "Power tools")
      account.stock_adjustments.create!(branch: main, product: product, quantity: main_stock, reason: "opening") if main_stock.positive?
      account.stock_adjustments.create!(branch: yard, product: product, quantity: yard_stock, reason: "opening") if yard_stock.positive?
    end

    products = account.products.index_by(&:sku)
    contractor = account.price_lists.find_by!(name: "Contractor")
    products["CEM-BAM-50"].price_list_items.create!(account: account, price_list: contractor, price: 820)
    products["CEM-BAM-50"].price_list_items.create!(account: account, min_quantity: 100, price: 830)
    products["STL-Y12"].price_list_items.create!(account: account, price_list: contractor, price: 1100)
    products["SCR-815"].product_units.create!(account: account, unit: unit.("Box"), quantity: 200, price: 850)
    products["PVC-2"].barcodes.create!(account: account, code: "6164000200017")

    kit = account.products.create!(name: "Bathroom plumbing kit", sku: "KIT-BATH", unit: unit.("Set"), price: 4950, kit: true,
      category: account.categories.find_by!(name: "Plumbing"))
    { "PPR-20" => 5, "PLB-GV34" => 1, "PLB-TAP12" => 2 }.each { |sku, qty| kit.kit_components.create!(account: account, component: products[sku], quantity: qty) }

    # The till: quick-pick buttons, customers, and the owner's approval PIN (2468) for discounts, voids and returns.
    %w[ CEM-BAM-50 STL-Y12 NAIL-4 NAIL-ROOF PVC-2 PPR-20 SCR-815 PNT-BR3 ELC-LED9 ELC-SW1 TL-TAPE5 SEC-PL50 ].each { |sku| products[sku].update!(quick_pick: true) }
    mwangi = account.customers.create!(name: "Mwangi Builders Ltd", phone: "0722 000 111", email: "accounts@mwangi.test", tax_pin: "P051234567X",
      price_list: contractor, credit_limit: 250_000, payment_terms_days: 30, address: "Plot 12, Mombasa Road, Nairobi")
    grace = account.customers.create!(name: "Grace Wambui", phone: "0733 000 222", email: "grace@wambui.test", address: "Kiambu Road, Ridgeways")
    otieno = account.customers.create!(name: "Otieno & Sons Contractors", phone: "0711 000 333", email: "office@otieno-sons.test",
      price_list: contractor, credit_limit: 80_000, payment_terms_days: 14, address: "Site 4, Ruiru Bypass")
    account.memberships.find_by!(user: owner).set_approval_pin("2468")
    account.update!(receipt_footer: "Goods sold are returnable within 7 days with this receipt.")

    # Purchasing: suppliers, what they supply, an order on its way, a delivery received, and invoices to pay.
    suppliers = {
      "Bamburi Cement Distributors" => { email: "orders@bamburi-dist.test", contact_name: "Peter Otieno", phone: "0722 100 200", payment_terms_days: 30,
        products: { "CEM-BAM-50" => [ 740, 2, 50 ], "CEM-SAV-50" => [ 690, 3, 50 ] } },
      "Devki Steel Mills" => { email: "sales@devki.test", contact_name: "Asha Patel", phone: "0733 300 400", payment_terms_days: 45,
        products: { "STL-Y12" => [ 960, 7, 100 ], "STL-Y10" => [ 690, 7, 100 ], "STL-BRC142" => [ 5800, 10, 10 ], "STL-BW25" => [ 3650, 7, 5 ] } },
      "Kentube Plumbing Supplies" => { email: "orders@kentube.test", contact_name: "Samuel Kariuki", payment_terms_days: 14,
        products: { "PVC-2" => [ 880, 5, 10 ], "PVC-4" => [ 1850, 5, 5 ], "PPR-20" => [ 250, 5, 20 ], "PLB-GV34" => [ 950, 10, 5 ], "PLB-TAP12" => [ 620, 10, 6 ] } },
      "Crown Paints Depot" => { email: "trade@crown-depot.test", payment_terms_days: 30,
        products: { "PNT-CRN-W20" => [ 7500, 4, 4 ], "PNT-CRN-B4" => [ 2500, 4, 6 ] } }
    }.to_h do |name, details|
      supplier = account.suppliers.create!(name: name, **details.except(:products))
      details[:products].each do |sku, (cost, lead_time, minimum)|
        supplier.supplier_products.create!(account: account, product: products[sku], cost: ex_vat.(cost), lead_time_days: lead_time, min_order_quantity: minimum, preferred: true)
      end
      [ name, supplier ]
    end

    steel_order = account.purchase_orders.create!(supplier: suppliers["Devki Steel Mills"], branch: main, expected_on: 3.days.from_now.to_date,
      note: "Deliver to the back gate", lines_attributes: [ { product_code: "STL-Y10", quantity: 200 }, { product_code: "STL-BRC142", quantity: 10 } ])
    steel_order.mark_sent

    cement_order = account.purchase_orders.create!(supplier: suppliers["Bamburi Cement Distributors"], branch: main,
      lines_attributes: [ { product_code: "CEM-SAV-50", quantity: 100 } ])
    cement_order.mark_sent
    delivery = account.goods_receipts.create!(supplier: cement_order.supplier, branch: main, purchase_order: cement_order,
      supplier_reference: "DN-88213", extra_costs: 2500,
      lines_attributes: [ { purchase_order_line: cement_order.lines.first, quantity: 100, unit_cost: ex_vat.(690) } ])

    account.supplier_invoices.create!(supplier: suppliers["Bamburi Cement Distributors"], goods_receipt: delivery, number: "BCD-40551",
      invoice_date: 40.days.ago.to_date, total: 71_500, tax: 9_862.07)
    account.supplier_invoices.create!(supplier: suppliers["Kentube Plumbing Supplies"], number: "KT-2291", invoice_date: 5.days.ago.to_date, total: 18_400)
    account.supplier_invoices.create!(supplier: suppliers["Devki Steel Mills"], number: "DSM-0931", invoice_date: 100.days.ago.to_date, total: 96_000)
    suppliers["Devki Steel Mills"].supplier_payments.create!(account: account, paid_on: 20.days.ago.to_date, amount: 50_000,
      payment_method: "bank_transfer", reference: "EFT 55120")

    # Customer accounts: past account sales (one overdue), a payment, a quote, an order with a deposit, and a delivery.
    front_counter = account.registers.find_by!(name: "Front counter")
    account_sale = ->(customer, days_ago, items) do
      shift = account.shifts.create!(register: front_counter, opening_float: 5000, opened_at: days_ago.days.ago)
      sale = shift.current_sale
      sale.change_customer(customer)
      items.each { |sku, quantity| sale.add(products[sku], quantity: quantity) }
      sale.pay(tender: "on_account", credit_approver: owner)
      sale.update_columns(completed_at: days_ago.days.ago, created_at: days_ago.days.ago)
      shift.close(counted_cash_cents: 5000_00)
      sale
    end
    account_sale.(mwangi, 50, { "CEM-BAM-50" => 60, "STL-Y12" => 40 })
    delivered = account_sale.(mwangi, 12, { "STL-BRC142" => 6, "NAIL-4" => 10 })
    account_sale.(otieno, 25, { "PVC-2" => 12, "PPR-20" => 30 })
    mwangi.customer_payments.create!(account: account, paid_on: 20.days.ago.to_date, amount: 40_000, payment_method: "bank_transfer", reference: "EFT 77301")

    note = account.delivery_notes.create!(sale: delivered, contact_phone: "0722 000 111", note: "Ask for the site foreman")
    note.dispatch(driver_name: "Joseph Mutua", vehicle: "KDA 123B")
    note.deliver(received_by: "Peter (site foreman)")
    account.delivery_notes.create!(sale: delivered, address: "Plot 12, Mombasa Road, Nairobi", note: "Second drop: balance of the mesh")

    account.customer_orders.create!(branch: main, customer: grace, note: "Delivery to Ridgeways can be arranged",
      lines_attributes: [ { product_code: "PNT-CRN-W20", quantity: 3 }, { product_code: "TL-TAPE5", quantity: 1 }, { product_code: "ELC-LED9", quantity: 12 } ])
    order = account.customer_orders.create!(branch: main, customer: otieno, needed_by: 5.days.from_now.to_date, note: "Special order: 4-inch pipes for the Ruiru site",
      lines_attributes: [ { product_code: "PVC-4", quantity: 20 }, { product_code: "PLB-GV34", quantity: 4 } ])
    order.take_deposit(amount_cents: 15_000_00, tender: "mobile_money", reference: "SJK4H7T2QP")
    order.mark_ready

    # A month of trading at both branches, so the dashboard and reports have something to show: counter sales through
    # the day, a few discounts, a void and a return, and each day's shift closed with its cash count.
    random = Random.new(2026)
    cashier = account.users.find_by!(email_address: "cashier@demo.test")
    counter_skus = %w[ CEM-BAM-50 NAIL-4 NAIL-ROOF PPR-20 PVC-2 SCR-815 PNT-BR3 ELC-LED9 ELC-SW1 TL-TAPE5 SEC-PL50 TL-HAM16 PLB-TAP12 PNT-CRN-B4 ]
    yard_skus = %w[ CEM-BAM-50 CEM-SAV-50 STL-Y12 STL-Y10 STL-BW25 ROOF-G30-3M ROOF-RIDGE NAIL-ROOF STL-BRC142 ]
    Time.use_zone(account.time_zone) do
    { front_counter => [ counter_skus, 6..11 ], account.registers.find_by!(name: "Yard gate") => [ yard_skus, 2..5 ] }.each do |register, (skus, per_day)|
      29.downto(0) do |days_ago|
        day = days_ago.days.ago.to_date
        next if day.sunday?

        opens = day.in_time_zone.change(hour: 8)
        shift = account.shifts.create!(register: register, opening_float: 5000, opened_at: opens, opened_by: days_ago.even? ? cashier : owner)
        count = random.rand(per_day)
        count = [ count, Time.current.hour - 8 ].min if days_ago.zero?
        count.times do |index|
          Current.user = shift.opened_by
          sale = shift.current_sale
          random.rand(1..3).times do
            sku = skus.sample(random: random)
            quantity = %w[ CEM-BAM-50 CEM-SAV-50 STL-Y12 STL-Y10 ].include?(sku) ? random.rand(2..25) : random.rand(1..6)
            sale.add(products[sku], quantity: quantity)
          end
          # A small discount within the cashier's limit most days, and now and then a bigger one a manager approved.
          sale.update!(discount_cents: (sale.subtotal_cents * 0.03).round) && sale.recalculate if index == 3
          sale.update!(discount_cents: (sale.subtotal_cents * 0.08).round, discount_approver: owner, approved_discount_percent: 8) && sale.recalculate if index == 1 && days_ago % 5 == 0
          tender = %w[ cash cash cash mobile_money mobile_money card ].sample(random: random)
          sale.pay(tender: tender, reference: (tender == "cash" ? nil : "SK#{random.rand(10**8)}"))
          sold_at = opens + ((index + 0.5) * 9.0 / count).hours + random.rand(0..20).minutes
          sold_at = [ sold_at, Time.current - (count - index).minutes ].min if days_ago.zero?
          sale.update_columns(completed_at: sold_at, created_at: sold_at)
          StockMovement.where(source: sale).update_all(created_at: sold_at)
        end
        next if days_ago.zero?

        if days_ago == 9 && register == front_counter && (voided = shift.sales.completed.last)
          voided.void(reason: "Rang up twice", by: owner)
          voided.update_columns(voided_at: voided.completed_at + 5.minutes)
          StockMovement.where(source: voided).update_all(created_at: voided.completed_at + 5.minutes)
        end
        if days_ago == 6 && register == front_counter && (returned = shift.sales.completed.first)
          sale_return = account.sale_returns.create!(sale: returned, shift: shift, refund_method: "cash", approver: owner, reason: "Wrong size",
            lines_attributes: [ { sale_line: returned.lines.first, quantity: 1, restock: true } ])
          sale_return.update_columns(created_at: opens + 9.hours)
          StockMovement.where(source: sale_return).update_all(created_at: opens + 9.hours)
        end
        shift.close(counted_cash_cents: shift.expected_cash_cents_now + [ 0, 0, 0, -5000, 2000, -20000 ].sample(random: random), by: shift.opened_by)
        shift.update_columns(closed_at: opens + 10.hours)
      end
    end
    end
    Current.user = owner

    # The month's deliveries: anything sold below zero is restocked to where it started.
    opening = catalogue.to_h { |_, sku, *, main_stock, yard_stock| [ sku, { main.id => main_stock, yard.id => yard_stock } ] }
    account.stock_levels.where("quantity < 0").includes(:product).each do |level|
      level.product.move_stock(branch: level.branch, quantity: opening.dig(level.product.sku, level.branch_id).to_d - level.quantity,
        reason: "received", note: "Weekly delivery")
    end

    # Integrations, all on simulators: an M-Pesa Paybill with payments that arrived on it (one for the order, one
    # paying Mwangi's account, one to use at the till), KRA eTIMS at Moi Avenue, and SMS.
    paybill = account.mpesa_shortcodes.create!(name: "Main Paybill", shortcode: "174379", environment: "simulator", c2b_registered_at: Time.current)
    { "SJQ82KD91L" => [ "2500.00", "", "PETER KAMAU", 25 ], "SJR11PL02X" => [ "5000.00", order.reference, "JAMES OTIENO", 70 ],
      "SJS55AB07Q" => [ "12000.00", "0722000111", "JOHN MWANGI", 95 ] }.each do |trans_id, (amount, reference, name, minutes_ago)|
      paybill.receive_c2b_confirmation("TransID" => trans_id, "TransAmount" => amount, "BillRefNumber" => reference, "FirstName" => name,
        "MSISDN" => "2547#{random.rand(10**8).to_s.rjust(8, "0")}", "TransTime" => minutes_ago.minutes.ago.in_time_zone("Nairobi").strftime("%Y%m%d%H%M%S"))
    end
    account.etims_devices.create!(branch: main, environment: "simulator", tin: "P051234567X", serial_number: "HPDEMO-MOI-01").initialize_with_kra
    account.update!(sms_enabled: true)

    products["CEM-BAM-50"].move_stock(branch: main, quantity: -3, reason: "damaged", note: "Bags split in the rain")
    account.stock_transfers.create!(from_branch: yard, to_branch: main, note: "Tuesday lorry",
      lines_attributes: [ { product_code: "CEM-BAM-50", quantity: 60 }, { product_code: "STL-Y10", quantity: 40 } ])
    account.stock_counts.create!(branch: main, category: account.categories.find_by!(name: "Hand tools")).tap do |count|
      count.lines.joins(:product).where(products: { sku: %w[ TL-HAM16 TL-TAPE5 ] }).each { |line| line.update!(counted_quantity: [ line.expected_quantity - 1, 0 ].max) }
    end
  ensure
    Current.reset
  end

  User.create!(name: "Platform Admin", email_address: "admin@hardpoint.test", password: "hardpoint-demo", admin: true,
    two_factor_secret: DEV_ADMIN_TWO_FACTOR_SECRET, two_factor_enabled_at: Time.current)
end
