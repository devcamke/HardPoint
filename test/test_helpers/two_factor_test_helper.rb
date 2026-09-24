module TwoFactorTestHelper
  def current_code(secret)
    ROTP::TOTP.new(secret).now
  end

  # Turns two-factor on for +user+ and returns the secret.
  def enable_two_factor_for(user)
    secret = User.generate_two_factor_secret
    travel_to(1.minute.ago) { user.enable_two_factor(secret, current_code(secret)) }
    secret
  end
end

ActiveSupport.on_load(:active_support_test_case) { include TwoFactorTestHelper }
