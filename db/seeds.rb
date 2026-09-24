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
  ensure
    Current.reset
  end

  User.create!(name: "Platform Admin", email_address: "admin@hardpoint.test", password: "hardpoint-demo", admin: true,
    two_factor_secret: DEV_ADMIN_TWO_FACTOR_SECRET, two_factor_enabled_at: Time.current)
end
