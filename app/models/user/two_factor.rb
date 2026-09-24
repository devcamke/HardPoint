# Time-based one-time passwords (TOTP) from an authenticator app, plus single-use recovery codes.
module User::TwoFactor
  extend ActiveSupport::Concern

  ISSUER = "HardPoint"
  DRIFT = 30.seconds
  RECOVERY_CODE_COUNT = 10

  included do
    encrypts :two_factor_secret, :two_factor_recovery_codes
  end

  class_methods do
    def generate_two_factor_secret
      ROTP::Base32.random
    end
  end

  def two_factor_enabled?
    two_factor_enabled_at.present?
  end

  def two_factor_provisioning_uri(secret)
    ROTP::TOTP.new(secret, issuer: ISSUER).provisioning_uri(email_address)
  end

  # Turns two-factor on once the person proves their app produces codes for +secret+.
  # Returns the new recovery codes (shown once), or nil if the code was wrong.
  def enable_two_factor(secret, code)
    if timestamp = verify_totp(secret, code)
      recovery_codes = generate_recovery_codes
      update! two_factor_secret: secret, two_factor_enabled_at: Time.current,
        two_factor_last_used_at: timestamp, two_factor_recovery_codes: recovery_codes.join("\n")
      track_two_factor_event "two_factor_enabled"
      recovery_codes
    end
  end

  def disable_two_factor
    update! two_factor_secret: nil, two_factor_enabled_at: nil, two_factor_last_used_at: nil, two_factor_recovery_codes: nil
    track_two_factor_event "two_factor_disabled"
  end

  # Accepts a current code from the app (each one only once) or an unused recovery code.
  def verify_two_factor(code)
    return false unless two_factor_enabled?

    with_lock do
      if timestamp = verify_totp(two_factor_secret, code, after: two_factor_last_used_at)
        update! two_factor_last_used_at: timestamp
      else
        consume_recovery_code(code)
      end
    end
  end

  def remaining_recovery_codes
    two_factor_recovery_codes.to_s.split("\n").size
  end

  private
    def verify_totp(secret, code, after: nil)
      ROTP::TOTP.new(secret, issuer: ISSUER).verify(code.to_s.gsub(/\s/, ""), drift_behind: DRIFT, after: after)
    end

    def generate_recovery_codes
      Array.new(RECOVERY_CODE_COUNT) { SecureRandom.alphanumeric(10).downcase.scan(/.{5}/).join("-") }
    end

    def consume_recovery_code(code)
      codes = two_factor_recovery_codes.to_s.split("\n")
      normalized = code.to_s.strip.downcase

      if normalized.present? && codes.include?(normalized)
        update! two_factor_recovery_codes: (codes - [ normalized ]).join("\n")
      else
        false
      end
    end

    def track_two_factor_event(action)
      track_event action if Current.account
    end
end
