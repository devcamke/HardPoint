require "test_helper"

# Which limits are per address and which per person or login, so an attacker elsewhere can't lock someone out
# and can't get round a limit by moving address or signing in again.
class SignInRateLimitsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  # Tests use a null cache, which never counts; count in memory for these tests only.
  setup do
    counts = ActiveSupport::Cache::MemoryStore.new
    ApplicationController.cache_store.define_singleton_method(:increment) { |*args, **options| counts.increment(*args, **options) }
  end

  teardown { ApplicationController.cache_store.singleton_class.remove_method(:increment) }

  def from(address) = { "REMOTE_ADDR" => address }

  test "guessing an owner's password from elsewhere doesn't lock the owner out of the shop" do
    use_account accounts(:acme)
    10.times { post session_path, params: { email_address: users(:amina).email_address, password: "wrong" }, env: from("203.0.113.9") }
    post session_path, params: { email_address: users(:amina).email_address, password: "password" }, env: from("203.0.113.9")
    assert_equal "Try again later.", flash[:alert]

    post session_path, params: { email_address: users(:amina).email_address, password: "password" }, env: from("198.51.100.4")
    assert cookies[:session_id].present?, "Amina still signs in at her shop"
  end

  test "reset emails to one address are limited, wherever they're asked for from" do
    use_account accounts(:acme)
    assert_enqueued_emails 5 do
      8.times { |i| post passwords_path, params: { email_address: users(:amina).email_address }, env: from("203.0.113.#{i}") }
    end
  end

  test "an administrator's password and codes are limited per login, not only per address" do
    host! "admin.localhost"
    10.times { |i| post admin_session_path, params: { email_address: users(:ada).email_address, password: "wrong" }, env: from("203.0.113.#{i}") }
    post admin_session_path, params: { email_address: users(:ada).email_address, password: "password" }, env: from("198.51.100.4")
    assert_equal "Try again later.", flash[:alert]
  end

  test "an administrator's two-factor codes are limited per administrator" do
    host! "admin.localhost"
    post admin_session_path, params: { email_address: users(:ada).email_address, password: "password" }
    9.times { |i| post admin_two_factor_path, params: { code: "000000" }, env: from("203.0.113.#{i}") }
    post admin_two_factor_path, params: { code: "000000" }, env: from("203.0.113.99")
    post admin_two_factor_path, params: { code: current_code(users(:ada).two_factor_secret) }, env: from("198.51.100.4")
    assert_equal "Try again later.", flash[:alert]
  end

  test "changing your password and two-factor are limited per person, not per till" do
    sign_in_as users(:amina)
    10.times { patch my_password_path, params: { current_password: "wrong", password: "a new long password", password_confirmation: "a new long password" }, env: from("203.0.113.1") }

    open_session do |other_till|
      other_till.host! "acme.localhost"
      other_till.post session_path, params: { email_address: users(:amina).email_address, password: "password" }, env: from("198.51.100.4")
      other_till.patch my_password_path, params: { current_password: "password", password: "a new long password", password_confirmation: "a new long password" }, env: from("198.51.100.4")
      assert_equal "Try again later.", other_till.flash[:alert]

      10.times { other_till.delete my_two_factor_path, params: { password: "wrong" }, env: from("198.51.100.4") }
    end

    delete my_two_factor_path, params: { password: "wrong" }, env: from("203.0.113.1")
    assert_equal "Try again later.", flash[:alert]
  end

  test "approval PIN tries are counted per person, so signing in again doesn't start afresh" do
    sign_in_as users(:amina)
    10.times { patch my_approval_pin_path, params: { approval_pin: "2468", password: "wrong" } }

    sign_out
    sign_in_as users(:amina)
    patch my_approval_pin_path, params: { approval_pin: "2468", password: "password" }
    assert_equal "Try again later.", flash[:alert]
    assert_nil Account.without_isolation { memberships(:amina_acme).reload.approval_pin_digest }
  end
end
