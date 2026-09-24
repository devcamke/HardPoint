# Development data: a demo shop at http://demo.localhost:3000 (sign in as owner@demo.test / "hardpoint-demo").
if Rails.env.development? && !Account.exists?(subdomain: "demo")
  Signup.new(shop_name: "Demo Hardware", subdomain: "demo", owner_name: "Demo Owner",
    email_address: "owner@demo.test", password: "hardpoint-demo").save!

  account = Account.find_by!(subdomain: "demo")
  Current.set(account: account) do
    account.branches.create!(name: "Timber yard", address: "Industrial Area")
    account.memberships.create!(role: :cashier, user_attributes: { name: "Carol Cashier", email_address: "cashier@demo.test" })
  end
end
