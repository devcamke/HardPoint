require "test_helper"

# A login made at sign-up is only a claim on its email address until the address is shown to be theirs, so
# nobody can open a throwaway shop as someone's address and walk into the real shop that adds them later.
class EmailOwnershipTest < ActionDispatch::IntegrationTest
  def sign_up(email_address, password: "the claimant's password", subdomain: "throwaway")
    use_apex_domain
    perform_enqueued_jobs do
      post signup_path, params: { signup: { shop_name: "Throwaway", subdomain: subdomain, owner_name: "Claimant",
        email_address: email_address, password: password, plan: "starter", terms_accepted: "1" } }
    end
  end

  test "signing up sends a link that confirms the address" do
    sign_up "wanjiru@mjengo.test"
    user = User.find_by!(email_address: "wanjiru@mjengo.test")
    assert_not user.email_confirmed?

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "wanjiru@mjengo.test" ], mail.to
    link = mail.text_part.body.to_s[%r{http://throwaway\.localhost/email_confirmations/\S+}]
    assert link

    use_account Account.without_isolation { Account.find_by!(subdomain: "throwaway") }
    get URI(link).path
    assert_redirected_to new_session_path
    assert user.reload.email_confirmed?

    get URI(link).path
    assert_equal "That link has expired or was already used.", flash[:alert]
  end

  test "a shop adding an address nobody has confirmed takes the login back: the inbox chooses the password" do
    sign_up "accountant@acme.test"
    claimant = User.find_by!(email_address: "accountant@acme.test")
    claimant_session = Account.without_isolation { Session.create!(account: claimant.accounts.sole, user: claimant) }

    sign_in_as users(:amina), account: accounts(:acme)
    perform_enqueued_jobs do
      post memberships_path, params: { membership: { role: "accountant", user_attributes: { name: "Real accountant", email_address: "accountant@acme.test" } } }
    end

    assert_not claimant.reload.authenticate("the claimant's password"), "the claimant's password no longer works"
    assert_not Account.without_isolation { Session.exists?(claimant_session.id) }, "and they're signed out"
    invitation = ActionMailer::Base.deliveries.last
    assert_match "Choose your password", invitation.text_part.body.to_s

    sign_out
    use_account accounts(:acme)
    post session_path, params: { email_address: "accountant@acme.test", password: "the claimant's password" }
    assert_nil cookies[:session_id].presence
  end

  test "choosing a password from an emailed link confirms the address" do
    user = Account.without_isolation { User.create!(name: "Njeri", email_address: "njeri@acme.test", password: SecureRandom.base58(32)) }
    use_account accounts(:acme)
    Account.without_isolation { accounts(:acme).memberships.create!(user: user, role: "cashier") }

    put password_path(user.password_reset_token), params: { password: "a new long password", password_confirmation: "a new long password" }
    assert user.reload.email_confirmed?
  end

  test "someone with a confirmed address keeps their password when another shop adds them" do
    sign_in_as users(:amina), account: accounts(:acme)
    post memberships_path, params: { membership: { role: "cashier", user_attributes: { name: "Bob", email_address: users(:bob).email_address } } }
    assert users(:bob).reload.authenticate("password")
  end
end

class SignupRateLimitTest < ActionDispatch::IntegrationTest
  setup do
    counts = ActiveSupport::Cache::MemoryStore.new
    SignupsController.cache_store.define_singleton_method(:increment) { |*args, **options| counts.increment(*args, **options) }
    use_apex_domain
  end

  teardown { SignupsController.cache_store.singleton_class.remove_method(:increment) }

  test "an existing login's password can't be guessed through sign-up" do
    5.times do |i|
      post signup_path, params: { signup: { shop_name: "Guess #{i}", subdomain: "guess#{i}", owner_name: "Eve",
        email_address: users(:amina).email_address, password: "guess #{i}", terms_accepted: "1" } }
    end
    post signup_path, params: { signup: { shop_name: "Guess", subdomain: "guess", owner_name: "Eve",
      email_address: users(:amina).email_address, password: "password", terms_accepted: "1" } }

    assert_equal "Try again later.", flash[:alert]
    assert_nil Account.without_isolation { Account.find_by(subdomain: "guess") }
  end
end
