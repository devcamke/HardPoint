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

    # A small hardware catalogue: name, SKU, category, brand, unit, price, cost, reorder level, stock at Moi Avenue, stock at the yard
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
      product = account.products.create!(name: name, sku: sku, unit: unit.(unit_name), price: price, cost: cost, reorder_level: reorder,
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
    account.customers.create!(name: "Mwangi Builders Ltd", phone: "0722 000 111", email: "accounts@mwangi.test", tax_pin: "P051234567X",
      price_list: contractor, credit_limit: 250_000)
    account.customers.create!(name: "Grace Wambui", phone: "0733 000 222")
    account.memberships.find_by!(user: owner).set_approval_pin("2468")
    account.update!(receipt_footer: "Goods sold are returnable within 7 days with this receipt.")

    products["CEM-BAM-50"].move_stock(branch: main, quantity: -3, reason: "damaged", note: "Bags split in the rain")
    account.stock_transfers.create!(from_branch: yard, to_branch: main, note: "Tuesday lorry",
      lines_attributes: [ { product_code: "CEM-BAM-50", quantity: 60 }, { product_code: "STL-Y10", quantity: 40 } ])
    account.stock_counts.create!(branch: main, category: account.categories.find_by!(name: "Hand tools")).tap do |count|
      count.lines.joins(:product).where(products: { sku: %w[ TL-HAM16 TL-TAPE5 ] }).each { |line| line.update!(counted_quantity: line.expected_quantity - 1) }
    end
  ensure
    Current.reset
  end

  User.create!(name: "Platform Admin", email_address: "admin@hardpoint.test", password: "hardpoint-demo", admin: true,
    two_factor_secret: DEV_ADMIN_TWO_FACTOR_SECRET, two_factor_enabled_at: Time.current)
end
