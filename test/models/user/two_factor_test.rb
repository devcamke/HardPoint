require "test_helper"

class User::TwoFactorTest < ActiveSupport::TestCase
  setup { @user = users(:amina) }

  test "turning on needs a correct code and returns recovery codes" do
    secret = User.generate_two_factor_secret

    assert_nil @user.enable_two_factor(secret, "000000")
    assert_not @user.reload.two_factor_enabled?

    codes = @user.enable_two_factor(secret, current_code(secret))
    assert_equal User::TwoFactor::RECOVERY_CODE_COUNT, codes.size
    assert @user.reload.two_factor_enabled?
  end

  test "the secret is encrypted at rest" do
    secret = enable_two_factor_for(@user)

    stored = User.connection.select_value("SELECT two_factor_secret FROM users WHERE id = #{@user.id}")
    assert_not_includes stored, secret
  end

  test "each code works only once" do
    secret = enable_two_factor_for(@user)
    code = current_code(secret)

    assert @user.verify_two_factor(code)
    assert_not @user.verify_two_factor(code)
  end

  test "recovery codes work once each" do
    enable_two_factor_for(@user)
    code = @user.two_factor_recovery_codes.split("\n").first

    assert @user.verify_two_factor(code.upcase)
    assert_not @user.verify_two_factor(code)
    assert_equal User::TwoFactor::RECOVERY_CODE_COUNT - 1, @user.remaining_recovery_codes
  end

  test "turning off clears everything" do
    enable_two_factor_for(@user)
    @user.disable_two_factor

    assert_not @user.reload.two_factor_enabled?
    assert_nil @user.two_factor_secret
    assert_not @user.verify_two_factor("123456")
  end
end
