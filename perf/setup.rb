# Builds the "loadtest" shop the k6 scenario sells in: Enterprise plan, two branches, one till and
# one cashier per virtual user, and 20,000 products (a big shop's catalogue) with barcodes and stock. Safe to run again.
#
#   TILLS=40 bin/rails runner perf/setup.rb
#
# Writes perf/loadtest.json (tills, logins and barcodes) for perf/till.js. Never run in production.
abort "Not in production" if Rails.env.production?

TILLS = Integer(ENV.fetch("TILLS", 40))
PRODUCTS = Integer(ENV.fetch("PRODUCTS", 20_000))

# Names like a hardware shop's, so a search finds a handful of products the way it would at the till, not all of them.
ITEMS = %w[ cement nails pipe elbow tee socket valve tap wire cable bulb switch paint brush roller hinge lock bolt nut
  washer screw sheet board tile grout gutter bend union adaptor clip chain hook bracket plug hose fitting mesh rod padlock ]
MATERIALS = %w[ steel pvc brass galv copper chrome white black ]
PASSWORD = "loadtest-password"

unless Account.exists?(subdomain: "loadtest")
  Signup.new(terms_accepted: true, shop_name: "Load Test Hardware", subdomain: "loadtest", owner_name: "Load Owner",
    email_address: "owner@loadtest.test", password: PASSWORD, plan: "enterprise").save!
end
account = Account.find_by!(subdomain: "loadtest")

Account.without_isolation do
  Current.set(account: account) do
    Current.session = account.sessions.create!(user: User.find_by!(email_address: "owner@loadtest.test"))
    account.update!(plan: "enterprise", subscription_status: "active", current_period_ends_at: 1.year.from_now, onboarding_completed_at: Time.current)
    branches = [ account.branches.first, account.branches.find_or_create_by!(name: "Yard") ]

    if account.products.count < PRODUCTS
      csv = +"sku,name,category,unit,price,cost,barcode,stock\n"
      PRODUCTS.times { |i| csv << "LT-#{i},#{ITEMS[i % ITEMS.size].capitalize} #{MATERIALS[i / ITEMS.size % MATERIALS.size]} #{5 * (1 + i % 60)}mm no. #{i},Group #{i % 40},Piece,#{100 + i % 900},#{50 + i % 400},#{(6_000_000_000_000 + i)},100000\n" }
      branches.each do |branch|
        import = account.product_imports.create!(csv: csv, branch: branch, filename: "loadtest.csv")
        import.check
        import.update!(status: :importing)
        import.run
      end
    end

    tills = TILLS.times.map do |i|
      branch = branches[i % 2]
      register = account.registers.find_or_create_by!(branch: branch, name: "Till #{i + 1}")
      email = "cashier#{i + 1}@loadtest.test"
      unless (user = User.find_by(email_address: email))
        membership = account.memberships.create!(role: :cashier, user_attributes: { name: "Cashier #{i + 1}", email_address: email })
        user = membership.user
      end
      user.update!(password: PASSWORD)
      { email: email, password: PASSWORD, register_id: register.id }
    end

    barcodes = account.barcodes.limit(PRODUCTS).pluck(:code)
    File.write(Rails.root.join("perf/loadtest.json"), JSON.pretty_generate(host: "loadtest", tills: tills, barcodes: barcodes, searches: [ "cement", "pvc elb", "brass tap 15", "galv bolt 20mm", "LT-1234", "padl", "chrome hinge" ]))
    puts "loadtest shop: #{tills.size} tills, #{account.products.count} products, #{barcodes.size} barcodes"
  end
end
