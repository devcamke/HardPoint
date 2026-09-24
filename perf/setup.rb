# Builds the "loadtest" shop the k6 scenario sells in: Enterprise plan, two branches, one till and
# one cashier per virtual user, and 2,000 products with barcodes and stock. Safe to run again.
#
#   TILLS=40 bin/rails runner perf/setup.rb
#
# Writes perf/loadtest.json (tills, logins and barcodes) for perf/till.js. Never run in production.
abort "Not in production" if Rails.env.production?

TILLS = Integer(ENV.fetch("TILLS", 40))
PRODUCTS = Integer(ENV.fetch("PRODUCTS", 2_000))
PASSWORD = "loadtest-password"

unless Account.exists?(subdomain: "loadtest")
  Signup.new(shop_name: "Load Test Hardware", subdomain: "loadtest", owner_name: "Load Owner",
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
      PRODUCTS.times { |i| csv << "LT-#{i},Load item #{i},Group #{i % 40},Piece,#{100 + i % 900},#{50 + i % 400},#{(6_000_000_000_000 + i)},100000\n" }
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
    File.write(Rails.root.join("perf/loadtest.json"), JSON.pretty_generate(host: "loadtest", tills: tills, barcodes: barcodes, searches: %w[ load item group 12 34 ]))
    puts "loadtest shop: #{tills.size} tills, #{account.products.count} products, #{barcodes.size} barcodes"
  end
end
