# Lets a platform administrator sign in to a shop as one of its staff, for support.
# The administrator gets a signed link valid for one minute; following it starts a shop
# session that ends after an hour and is recorded in the shop's Activity.
class Impersonation
  TOKEN_EXPIRES_IN = 1.minute

  attr_reader :administrator, :membership

  def self.from_token(token)
    data = verifier.verified(token.to_s, purpose: :impersonation) or return

    administrator = User.find_by(id: data["administrator_id"], admin: true)
    membership = Current.account&.memberships&.find_by(id: data["membership_id"])
    new(administrator: administrator, membership: membership) if administrator && membership
  end

  def self.verifier
    Rails.application.message_verifier(:impersonation)
  end

  def initialize(administrator:, membership:)
    @administrator, @membership = administrator, membership
  end

  def token
    self.class.verifier.generate({ "administrator_id" => administrator.id, "membership_id" => membership.id },
      purpose: :impersonation, expires_in: TOKEN_EXPIRES_IN)
  end
end
