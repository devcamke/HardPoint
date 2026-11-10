require "test_helper"

# What HardPoint support can and can't do while signed in as someone, the platform's own audit trail, and the
# lockouts and links around signing in.
class SupportAndSignInSecurityTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def impersonate(user)
    Account.without_isolation { Session.where(user: user).update_all(impersonator_id: users(:ada).id, expires_at: 1.hour.from_now) }
  end

  def support_link_for(membership)
    sign_in_as_administrator
    post admin_impersonations_path, params: { membership_id: membership.id }
    Rack::Utils.parse_query(URI(response.location).query)["token"]
  end

  # --- Support signed in as someone ---

  test "support signed in as the owner can't add, change or remove staff" do
    sign_in_as users(:amina)
    impersonate users(:amina)

    assert_no_difference -> { Account.without_isolation { Membership.count } } do
      post memberships_path, params: { membership: { role: "owner", user_attributes: { name: "Mallory", email_address: "mallory@evil.test" } } }
    end
    assert_redirected_to memberships_path
    assert_equal "Not while HardPoint support is signed in as you.", flash[:alert]

    patch membership_path(memberships(:carl_acme)), params: { membership: { role: "manager" } }
    assert_equal "cashier", Account.without_isolation { memberships(:carl_acme).reload.role }

    delete membership_path(memberships(:carl_acme))
    assert Account.without_isolation { Membership.exists?(memberships(:carl_acme).id) }

    get memberships_path
    assert_response :success, "they can still look"
  end

  test "support signed in as someone can't set up or turn off their two-factor, or close the shop" do
    sign_in_as users(:amina)
    impersonate users(:amina)

    get new_my_two_factor_path
    assert_redirected_to my_profile_path
    post my_two_factor_path, params: { code: "123456" }
    assert_redirected_to my_profile_path
    assert_nil session[:new_recovery_codes]

    Account.without_isolation { enable_two_factor_for(users(:amina)) }
    delete my_two_factor_path, params: { password: "password", code: "aaaaa-11111" }
    assert_equal "Not while HardPoint support is signed in as you.", flash[:alert]
    assert users(:amina).reload.two_factor_enabled?

    post account_closure_path, params: { confirmation: "acme", password: "password" }
    assert_redirected_to account_data_path
    assert_not Account.without_isolation { accounts(:acme).reload.closing? }
  end

  test "what support does while signed in as someone shows who really did it" do
    sign_in_as users(:amina)
    impersonate users(:amina)
    patch branch_path(branches(:acme_yard)), params: { branch: { name: "Steel yard" } }

    event = Account.without_isolation { Event.where(eventable: branches(:acme_yard), action: "updated").last }
    assert_equal users(:ada).name, event.particulars["impersonated_by"]

    Account.without_isolation { Session.where(user: users(:amina)).update_all(impersonator_id: nil) }
    get events_path
    assert_select "li", /Amina Owner \(support: Ada Admin\) changed branch Steel yard/
  end

  # --- The admin audit trail and support links ---

  test "administrators' sign-ins and support links are recorded, and listed in the admin" do
    token = support_link_for(memberships(:carl_acme))

    assert AdminEvent.exists?(user: users(:ada), action: "signed_in")
    link = AdminEvent.find_by!(user: users(:ada), action: "impersonation_link_created")
    assert_equal accounts(:acme).id, link.target_account_id
    assert_equal "Carl Cashier", link.particulars["member"]
    assert_nil link.token_used_at

    use_account accounts(:acme)
    post session_impersonation_path, params: { token: token }
    assert link.reload.token_used_at

    host! "admin.localhost"
    get admin_events_path
    assert_response :success
    assert_select "tr", /Made a link to sign in to Acme Hardware\s+as Carl Cashier/
    assert_select "tr", /Signed in/
  end

  test "a support link works once" do
    token = support_link_for(memberships(:carl_acme))
    use_account accounts(:acme)

    post session_impersonation_path, params: { token: token }
    assert_redirected_to root_path
    delete session_path

    post session_impersonation_path, params: { token: token }
    assert_redirected_to new_session_path
    assert_equal "That support link has already been used.", flash[:alert]
    assert_equal 1, Account.without_isolation { Event.where(creator: users(:carl), action: "impersonation_started").count }
  end

  # --- Two-factor ---

  test "a shop can't reset a platform administrator's two-factor" do
    membership = Account.without_isolation { Current.set(account: accounts(:acme)) { accounts(:acme).memberships.create!(user: users(:ada), role: "cashier") } }

    assert_not membership.two_factor_resettable_by_shop?
    assert memberships(:carl_acme).two_factor_resettable_by_shop?
  end

  test "an administrator without two-factor can't set it up with only their password" do
    admin = User.create!(name: "New Admin", email_address: "new@hardpoint.test", password: "a long password", admin: true)
    host! "admin.localhost"
    post admin_session_path, params: { email_address: admin.email_address, password: "a long password" }
    get new_admin_two_factor_path
    assert_select "h1", "Two-factor isn't set up"
    assert_select "svg[role=img]", count: 0

    secret = User.generate_two_factor_secret
    post admin_two_factor_path, params: { code: current_code(secret) }
    assert_not admin.reload.two_factor_enabled?
    assert_nil cookies[:admin_session_id].presence
  end

  test "an administrator sets up two-factor with an enrolment link, which works once" do
    admin = User.create!(name: "New Admin", email_address: "new@hardpoint.test", password: "a long password", admin: true)
    token = admin.generate_token_for(:admin_enrolment)
    host! "admin.localhost"

    get new_admin_session_path(enrolment_token: token)
    post admin_session_path, params: { email_address: admin.email_address, password: "a long password" }
    get new_admin_two_factor_path
    assert_select "svg[role=img]"
    post admin_two_factor_path, params: { code: current_code(session[:pending_admin_two_factor_secret]) }
    assert_redirected_to admin_root_path
    assert admin.reload.two_factor_enabled?

    admin.disable_two_factor
    assert_nil User.find_by_token_for(:admin_enrolment, token), "the link was spent when two-factor was set up"
  end

  test "ten wrong two-factor codes lock sign-in for 15 minutes and email the person once; a right code resets the count" do
    secret = enable_two_factor_for(users(:amina))
    use_account accounts(:acme)
    post session_path, params: { email_address: users(:amina).email_address, password: "password" }

    post session_two_factor_path, params: { code: "000000" }
    post session_two_factor_path, params: { code: current_code(secret) }
    assert cookies[:session_id].present?
    assert_equal 0, users(:amina).reload.failed_two_factor_attempts
    delete session_path

    post session_path, params: { email_address: users(:amina).email_address, password: "password" }
    assert_enqueued_emails 1 do
      12.times { post session_two_factor_path, params: { code: "000000" } }
    end
    assert_match "Too many wrong codes", flash[:alert]
    assert users(:amina).reload.two_factor_locked?

    travel 1.minute
    post session_two_factor_path, params: { code: current_code(secret) }
    assert_match "Too many wrong codes", flash[:alert]
    assert cookies[:session_id].blank?

    travel User::TwoFactor::LOCKOUT
    post session_path, params: { email_address: users(:amina).email_address, password: "password" }
    post session_two_factor_path, params: { code: current_code(secret) }
    assert_redirected_to root_url
  end

  test "an administrator's wrong codes count towards the same lockout" do
    host! "admin.localhost"
    post admin_session_path, params: { email_address: users(:ada).email_address, password: "password" }
    10.times { post admin_two_factor_path, params: { code: "000000" } }

    assert users(:ada).reload.two_factor_locked?
    post admin_two_factor_path, params: { code: current_code(users(:ada).two_factor_secret) }
    assert_match "Too many wrong codes", flash[:alert]
  end

  test "turning two-factor off needs a code as well as the password" do
    secret = enable_two_factor_for(users(:amina))
    sign_in_as users(:amina), two_factor_secret: secret
    travel 31.seconds

    delete my_two_factor_path, params: { password: "password" }
    assert users(:amina).reload.two_factor_enabled?

    delete my_two_factor_path, params: { password: "password", code: "000000" }
    assert users(:amina).reload.two_factor_enabled?

    delete my_two_factor_path, params: { password: "password", code: current_code(secret) }
    assert_not users(:amina).reload.two_factor_enabled?
  end

  # --- Ending admin sessions ---

  test "changing or resetting a password, or turning two-factor off, ends admin sessions too" do
    AdminSession.create!(user: users(:amina))
    sign_in_as users(:amina)
    patch my_password_path, params: { current_password: "password", password: "a new long password", password_confirmation: "a new long password" }
    assert_equal 0, AdminSession.where(user: users(:amina)).count

    AdminSession.create!(user: users(:amina))
    put password_path(users(:amina).reload.password_reset_token), params: { password: "another long one", password_confirmation: "another long one" }
    assert_equal 0, AdminSession.where(user: users(:amina)).count

    Account.without_isolation { enable_two_factor_for(users(:amina)) }
    AdminSession.create!(user: users(:amina))
    users(:amina).reload.disable_two_factor
    assert_equal 0, AdminSession.where(user: users(:amina)).count
  end

  # --- Invitations ---

  test "an invitation's set-password link lasts days, and only until a password is chosen" do
    sign_in_as users(:amina)
    perform_enqueued_jobs do
      post memberships_path, params: { membership: { role: "cashier", user_attributes: { name: "Njeri", email_address: "njeri@acme.test" } } }
    end
    mail = ActionMailer::Base.deliveries.last
    assert_match "expires in 3 days", mail.text_part.body.to_s
    path = mail.text_part.body.to_s[%r{http://acme\.localhost(/passwords/\S+/edit)}, 1]

    travel 2.days
    get path
    assert_response :success

    put path.delete_suffix("/edit"), params: { password: "njeri's password", password_confirmation: "njeri's password" }
    assert_redirected_to new_session_path
    get path
    assert_redirected_to new_password_path, "used once"
  end

  test "an invitation link stops working after three days; a reset link still lasts minutes" do
    njeri = User.create!(name: "Njeri", email_address: "njeri@acme.test", password: SecureRandom.base58(32))
    Account.without_isolation { Current.set(account: accounts(:acme)) { accounts(:acme).memberships.create!(user: njeri, role: "cashier") } }
    invitation, reset = njeri.generate_token_for(:invitation), njeri.password_reset_token
    use_account accounts(:acme)

    travel 1.hour
    get edit_password_path(reset)
    assert_redirected_to new_password_path

    travel 3.days
    get edit_password_path(invitation)
    assert_redirected_to new_password_path
  end
end
