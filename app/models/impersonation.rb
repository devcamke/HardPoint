# Lets a platform administrator sign in to a shop as one of its staff, for support.
# The administrator gets a signed link valid for one minute and for one use; following it starts a shop
# session that ends after an hour and is recorded in the shop's Activity. Making the link is recorded in
# the platform's admin events, and that row remembers when the link was used.
class Impersonation
  TOKEN_EXPIRES_IN = 1.minute

  attr_reader :administrator, :membership, :token_id

  # Makes a link for +administrator+ to sign in as +membership+, and records it.
  def self.issue(administrator:, membership:, ip_address: nil)
    new(administrator: administrator, membership: membership, token_id: SecureRandom.uuid).tap do |impersonation|
      AdminEvent.record "impersonation_link_created", user: administrator, ip_address: ip_address, account: membership.account,
        member: membership.user.name, token_id: impersonation.token_id
    end
  end

  def self.from_token(token)
    data = verifier.verified(token.to_s, purpose: :impersonation) or return

    administrator = User.find_by(id: data["administrator_id"], admin: true)
    membership = Current.account&.memberships&.find_by(id: data["membership_id"])
    new(administrator: administrator, membership: membership, token_id: data["token_id"]) if administrator && membership
  end

  def self.verifier
    Rails.application.message_verifier(:impersonation)
  end

  def initialize(administrator:, membership:, token_id: nil)
    @administrator, @membership, @token_id = administrator, membership, token_id
  end

  def token
    self.class.verifier.generate({ "administrator_id" => administrator.id, "membership_id" => membership.id, "token_id" => token_id },
      purpose: :impersonation, expires_in: TOKEN_EXPIRES_IN)
  end

  # Spends the link: true the first time, false once it has been used (or if it was never recorded).
  def use
    AdminEvent.use_token(token_id)
  end
end
