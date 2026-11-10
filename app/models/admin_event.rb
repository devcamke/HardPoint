# The platform's audit trail: what HardPoint staff did in the admin area, as opposed to a shop's own Activity.
# Append-only (a link's token_used_at is set with update_all), and platform-wide (no row-level security): it's only read in the admin area.
class AdminEvent < ApplicationRecord
  belongs_to :user

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  def self.record(action, user:, ip_address: nil, account: nil, token_id: nil, **particulars)
    create! user: user, action: action, ip_address: ip_address, target_account_id: account&.id, token_id: token_id,
      particulars: particulars.merge(account: account&.name).compact
  end

  # Marks a support sign-in link used; true only the first time, so each link works once.
  def self.use_token(token_id)
    token_id.present? && where(token_id: token_id, token_used_at: nil).update_all(token_used_at: Time.current) == 1
  end

  def readonly?
    persisted?
  end
end
