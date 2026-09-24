require "test_helper"

class SignupTest < ActiveSupport::TestCase
  test "creates the shop, its owner and a first branch" do
    signup = Signup.new(shop_name: "Mjengo Hardware", subdomain: "Mjengo", owner_name: "Wanjiru",
      email_address: "wanjiru@mjengo.test", password: "a long password")

    assert signup.save

    account = signup.account
    assert_equal "mjengo", account.subdomain

    Current.account = account
    assert_equal [ "Main branch" ], account.branches.pluck(:name)
    assert account.memberships.sole.owner?
    assert_equal "wanjiru@mjengo.test", account.users.sole.email_address
    assert_equal [ account.users.sole ], account.account_events.map(&:creator).uniq, "Signup events are credited to the new owner"
  end

  test "an existing user can open another shop with their password" do
    signup = Signup.new(shop_name: "Bob's Second Shop", subdomain: "bob2", owner_name: "Bob",
      email_address: users(:bob).email_address, password: "password")

    assert_no_difference -> { User.count } do
      assert signup.save
    end

    assert_equal 2, Account.without_isolation { users(:bob).accounts.count }
  end

  test "an existing user's email can't be claimed without their password" do
    signup = Signup.new(shop_name: "Imposter", subdomain: "imposter", owner_name: "Eve",
      email_address: users(:bob).email_address, password: "not bob's password")

    assert_not signup.save
    assert_includes signup.errors[:email_address].first, "already has a HardPoint login"
  end

  test "reserved and taken subdomains are rejected" do
    assert_not Signup.new(shop_name: "x", subdomain: "www", owner_name: "x", email_address: "x@x.test", password: "a long password").save
    assert_not Signup.new(shop_name: "x", subdomain: "acme", owner_name: "x", email_address: "x@x.test", password: "a long password").save
  end

  test "failed signups leave nothing behind" do
    signup = Signup.new(shop_name: "x", subdomain: "fresh", owner_name: "", email_address: "fresh@x.test", password: "a long password")

    assert_no_difference -> { Account.count } do
      assert_not signup.save
    end
  end
end
