# An owner or manager approving something at someone else's till (a big discount, a void, a
# return) by typing their approval PIN. It authorises that one action; it signs nobody in.
module Approval
  APPROVER_ROLES = %w[ owner manager ].freeze

  def self.approver_for(account, pin)
    return if pin.blank?

    account.memberships.includes(:user).where(role: APPROVER_ROLES).where.not(approval_pin_digest: nil)
      .find { |membership| membership.authenticate_approval_pin(pin) }&.user
  end
end
