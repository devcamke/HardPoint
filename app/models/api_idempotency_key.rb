# The answer to a create request made with an Idempotency-Key header, kept for a day: sending the same
# request again gets the same answer instead of a second order; reusing the key for a different request
# is refused. A key is claimed (response_status 0) before the request does its work, so two identical
# requests arriving together can't both create: the second finds the claim and is told to retry.
class ApiIdempotencyKey < ApplicationRecord
  include AccountOwned

  RETENTION = 24.hours
  PENDING = 0

  belongs_to :api_key

  validates :key, presence: true, length: { maximum: 255 }

  # The claim for this key: a new pending one, the earlier finished one, or nil when another request holds
  # a pending claim right now. The unique index on (api_key, key) decides who was first.
  def self.claim(api_key, key, digest)
    api_key.idempotency_keys.create!(account: api_key.account, key: key, request_digest: digest, response_status: PENDING, response_body: {})
  rescue ActiveRecord::RecordNotUnique
    earlier = api_key.idempotency_keys.find_by(key: key)
    earlier unless earlier.nil? || earlier.pending?
  end

  def pending?
    response_status == PENDING
  end

  STALE_CLAIM = 2.minutes

  def self.purge_old
    Account.without_isolation do
      where(created_at: ...RETENTION.ago).delete_all
      where(response_status: PENDING, created_at: ...STALE_CLAIM.ago).delete_all
    end
  end
end
