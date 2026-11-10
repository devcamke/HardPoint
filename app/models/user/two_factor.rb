# Time-based one-time passwords (TOTP) from an authenticator app, plus single-use recovery codes.
module User::TwoFactor
  extend ActiveSupport::Concern

  ISSUER = "HardPoint"
  DRIFT = 30.seconds
  RECOVERY_CODE_COUNT = 10
  # Wrong codes in a row before codes stop being accepted for a while. Whoever is typing them got the password
  # right, so the person is emailed: it's time to change it.
  ATTEMPTS_ALLOWED = 10
  LOCKOUT = 15.minutes
  ADMIN_ENROLMENT_EXPIRES_IN = 1.day

  included do
    encrypts :two_factor_secret, :two_factor_recovery_codes

    # A platform administrator sets up two-factor on the web only with a link made on the server
    # (bin/rails admin:enrolment_link[email]), so their password alone never lets someone enrol their own phone.
    # Setting two-factor up changes both values, so a link works once.
    generates_token_for :admin_enrolment, expires_in: ADMIN_ENROLMENT_EXPIRES_IN do
      [ updated_at.iso8601(6), two_factor_enabled_at&.iso8601(6) ]
    end
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
    update! two_factor_secret: nil, two_factor_enabled_at: nil, two_factor_last_used_at: nil, two_factor_recovery_codes: nil,
      failed_two_factor_attempts: 0, two_factor_locked_until: nil
    # Two-factor is what guards the admin area, so a platform administrator without it is signed out of there.
    admin_sessions.delete_all
    track_two_factor_event "two_factor_disabled"
  end

  # Accepts a current code from the app (each one only once) or an unused recovery code. Every wrong code counts
  # towards a lockout, wherever it was typed (a shop's sign-in, the admin area, turning two-factor off).
  def verify_two_factor(code)
    return false unless two_factor_enabled?

    locked_now = false
    verified = with_lock do
      next false if two_factor_locked?

      if timestamp = verify_totp(two_factor_secret, code, after: two_factor_last_used_at)
        update! two_factor_last_used_at: timestamp, failed_two_factor_attempts: 0
      elsif consume_recovery_code(code)
        update! failed_two_factor_attempts: 0
      else
        locked_now = count_two_factor_failure
        false
      end
    end

    UsersMailer.with(user: self).two_factor_locked.deliver_later if locked_now
    verified
  end

  def two_factor_locked?
    two_factor_locked_until&.future?
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

    # True when this failure locks two-factor: the count starts again, so each lockout is emailed once.
    def count_two_factor_failure
      if failed_two_factor_attempts + 1 >= ATTEMPTS_ALLOWED
        update_columns failed_two_factor_attempts: 0, two_factor_locked_until: LOCKOUT.from_now
        true
      else
        update_columns failed_two_factor_attempts: failed_two_factor_attempts + 1
        false
      end
    end

    def track_two_factor_event(action)
      track_event action if Current.account
    end
end
