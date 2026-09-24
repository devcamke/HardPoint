# The answer to a create request made with an Idempotency-Key header, kept for a day: sending the same
# request again gets the same answer instead of a second order; reusing the key for a different request
# is refused.
class ApiIdempotencyKey < ApplicationRecord
  include AccountOwned

  RETENTION = 24.hours

  belongs_to :api_key

  validates :key, presence: true, length: { maximum: 255 }

  def self.purge_old
    Account.without_isolation { where(created_at: ...RETENTION.ago).delete_all }
  end
end
