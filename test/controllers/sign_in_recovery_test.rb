require "test_helper"

class SignInRecoveryTest < ActionDispatch::IntegrationTest
  def turn_on_two_factor(user)
    secret = User.generate_two_factor_secret
    Account.without_isolation { Current.set(account: accounts(:acme)) { user.enable_two_factor(secret, ROTP::TOTP.new(secret).now) } }
    secret
  end

  def sessions_of(user) = Account.without_isolation { user.sessions.count }

  test "changing your password checks the old one and signs you out everywhere else" do
    sign_in_as users(:carl)
    other = Account.without_isolation { Current.set(account: accounts(:acme)) { users(:carl).sessions.create!(account: accounts(:acme)) } }
    get my_profile_path
    assert_select "a[href=?]", edit_my_password_path, "Change password"

    patch my_password_path, params: { current_password: "wrong", password: "a new long password", password_confirmation: "a new long password" }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", /current password wasn't right/

    patch my_password_path, params: { current_password: "password", password: "short", password_confirmation: "short" }
    assert_select "[role=alert]", /at least 10 characters/

    patch my_password_path, params: { current_password: "password", password: "a new long password", password_confirmation: "another one" }
    assert_select "[role=alert]", /don't match/

    patch my_password_path, params: { current_password: "password", password: "a new long password", password_confirmation: "a new long password" }
    assert_redirected_to my_profile_path
    assert Account.without_isolation { users(:carl).reload.authenticate("a new long password") }
    assert_not Account.without_isolation { Session.exists?(other.id) }, "other sessions signed out"
    assert_equal 1, sessions_of(users(:carl))
    get my_profile_path
    assert_response :success, "this session stays signed in"
  end

  test "an owner resets two-factor for staff who lost their phone" do
    turn_on_two_factor(users(:carl))
    sign_in_as users(:amina)
    get edit_membership_path(memberships(:carl_acme))
    assert_select "input[type=submit][value='Reset two-factor']"

    post membership_two_factor_reset_path(memberships(:carl_acme)), params: { password: "wrong" }
    assert_equal "Your password wasn't right, so nothing was changed.", flash[:alert]
    assert Account.without_isolation { users(:carl).reload.two_factor_enabled? }

    perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) do
      post membership_two_factor_reset_path(memberships(:carl_acme)), params: { password: "password" }
    end
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ users(:carl).email_address ], mail.to
    assert_includes mail.text_part.body.to_s, "#{users(:amina).name} turned off two-factor sign-in"
    assert_redirected_to memberships_path
    assert_not Account.without_isolation { users(:carl).reload.two_factor_enabled? }
    assert_equal 0, sessions_of(users(:carl))

    get events_path
    assert_select "body", /reset #{users(:carl).name}'s two-factor sign-in/
  end

  test "a shop can't reset someone who also works for another shop, or itself; managers can't reset at all" do
    turn_on_two_factor(users(:carl))
    Account.without_isolation { Current.set(account: accounts(:bolt)) { accounts(:bolt).memberships.create!(user: users(:carl), role: "cashier") } }
    sign_in_as users(:amina)
    get edit_membership_path(memberships(:carl_acme))
    assert_match "also uses HardPoint with another shop", response.body
    post membership_two_factor_reset_path(memberships(:carl_acme)), params: { password: "password" }
    assert_match "only HardPoint support", flash[:alert]
    assert Account.without_isolation { users(:carl).reload.two_factor_enabled? }

    post membership_two_factor_reset_path(memberships(:amina_acme)), params: { password: "password" }
    assert_match "can't reset your own", flash[:alert]

    Account.without_isolation { memberships(:sara_acme).update!(role: "manager") }
    sign_in_as users(:sara)
    post membership_two_factor_reset_path(memberships(:carl_acme)), params: { password: "password" }
    assert_response :forbidden
  end

  test "HardPoint support resets a sole owner's two-factor" do
    turn_on_two_factor(users(:amina))
    sign_in_as_administrator
    get admin_account_path(accounts(:acme))
    assert_select "button", "Reset 2FA"

    post admin_account_two_factor_resets_path(accounts(:acme), membership_id: memberships(:amina_acme).id)
    assert_redirected_to admin_account_path(accounts(:acme))
    assert_not Account.without_isolation { users(:amina).reload.two_factor_enabled? }
    event = Account.without_isolation { Event.find_by!(account: accounts(:acme), action: "two_factor_reset") }
    assert_equal users(:ada).email_address, event.particulars["administrator"]
  end

  test "a customer added from the till goes on the sale and the cashier is back at the till" do
    sign_in_as users(:carl)
    post pos_till_path, params: { register_id: registers(:acme_front).id }
    get pos_customers_path(query: "0722 555 111")
    assert_select "a[href=?]", new_customer_path(for_till: 1, phone: "0722 555 111")

    get new_customer_path(for_till: 1, phone: "0722 555 111")
    assert_select "input[name=for_till]"
    assert_select "input[name='customer[phone]'][value='0722 555 111']"
    assert_select "a[href=?]", pos_path, "Back to the till"

    post customers_path, params: { for_till: "1", customer: { name: "Juma Fundi", phone: "0722 555 111" } }
    assert_redirected_to pos_path
    sale = Account.without_isolation { shifts(:acme_front_open).current_sale }
    assert_equal "Juma Fundi", Account.without_isolation { sale.customer.name }
  end
end
