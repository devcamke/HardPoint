# An owner or manager approving something at someone else's till (a big discount, a void, a
# return) by typing their approval PIN. It authorises that one action; it signs nobody in.
#
# Approval PINs are short, so wrong ones are counted per shop: after FAILURES_ALLOWED in WINDOW, no approval PIN
# is accepted until the window passes (owners and managers can still approve by signing in themselves). A wrong
# guess doesn't say whose PIN it was aimed at, so the count is the shop's rather than one person's.
module Approval
  APPROVER_ROLES = %w[ owner manager ].freeze
  FAILURES_ALLOWED = 10
  WINDOW = 15.minutes

  mattr_accessor :cache, default: nil

  def self.approver_for(account, pin)
    return if pin.blank? || locked?(account)

    approver = account.memberships.includes(:user).where(role: APPROVER_ROLES).where.not(approval_pin_digest: nil)
      .find { |membership| membership.authenticate_approval_pin(pin.to_s) }&.user
    approver || record_failure(account)
  end

  def self.locked?(account)
    store.read(key(account)).to_i >= FAILURES_ALLOWED
  end

  def self.record_failure(account)
    store.increment(key(account), 1, expires_in: WINDOW)
    nil
  end

  def self.key(account) = "approval-pin-failures/#{account.id}"
  def self.store = cache || Rails.cache
end
