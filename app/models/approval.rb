# An owner or manager approving something at someone else's till (a big discount, a void, a
# return) by typing their approval PIN. It authorises that one action; it signs nobody in.
#
# Approval PINs are short, so wrong ones are counted per signed-in till (session): after FAILURES_ALLOWED in WINDOW,
# that till accepts no approval PIN until the window passes, while the shop's other tills carry on. Guessing spread
# over many sign-ins is caught by a larger count for the whole shop, SHOP_FAILURES_ALLOWED. A wrong guess doesn't
# say whose PIN it was aimed at, so neither count is one person's. Owners and managers can still approve by
# signing in themselves.
#
# No two approvers in a shop share a PIN (Membership refuses it), so a PIN always names one person.
module Approval
  APPROVER_ROLES = %w[ owner manager ].freeze
  FAILURES_ALLOWED = 10
  SHOP_FAILURES_ALLOWED = 50
  WINDOW = 15.minutes

  mattr_accessor :cache, default: nil

  def self.approver_for(account, pin, session: Current.session)
    return if pin.blank? || locked?(account, session)

    approver = holder_of(account, pin)&.user
    approver || record_failure(account, session)
  end

  # The owner or manager in this shop whose approval PIN this is.
  def self.holder_of(account, pin, except: nil)
    account.memberships.includes(:user).where(role: APPROVER_ROLES).where.not(approval_pin_digest: nil)
      .where.not(id: except&.id).find { |membership| membership.authenticate_approval_pin(pin.to_s) }
  end

  def self.locked?(account, session = nil)
    store.read(key(account)).to_i >= SHOP_FAILURES_ALLOWED || (session && store.read(key(account, session)).to_i >= FAILURES_ALLOWED)
  end

  def self.record_failure(account, session)
    store.increment(key(account), 1, expires_in: WINDOW)
    store.increment(key(account, session), 1, expires_in: WINDOW) if session
    nil
  end

  def self.key(account, session = nil) = [ "approval-pin-failures", account.id, session&.id ].compact.join("/")
  def self.store = cache || Rails.cache
end
