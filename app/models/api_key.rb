# A shop's key to the public API. The token is shown once, when the key is made; only its SHA-256
# digest is stored, so a stolen database doesn't give access. "read" keys can only read; "write"
# keys can also create and change products, customers and orders.
class ApiKey < ApplicationRecord
  include AccountOwned, Eventable

  PREFIX = "hp_"
  SCOPES = %w[ read write ].freeze
  LAST_USED_PRECISION = 1.minute

  belongs_to :creator, class_name: "User", default: -> { Current.user }, optional: true
  has_many :idempotency_keys, class_name: "ApiIdempotencyKey", dependent: :delete_all

  attr_reader :token

  validates :name, presence: true, length: { maximum: 60 }
  validates :scope, inclusion: { in: SCOPES }
  validate(on: :create) { errors.add :base, "The API is on the Business and Enterprise plans" unless account&.subscription_plan&.api? }

  before_validation :generate_token, on: :create
  after_create { track_event "created", scope: scope }

  scope :active, -> { where(revoked_at: nil) }
  scope :chronologically, -> { order(created_at: :desc) }

  # The active key a token belongs to, across shops (the request says which shop by its key).
  def self.authenticate(token)
    token = token.to_s
    return unless token.start_with?(PREFIX) && token.length > 20

    Account.without_isolation { active.includes(:account).find_by(token_digest: digest(token)) }
  end

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token)
  end

  def writable?
    scope == "write"
  end

  def revoked?
    revoked_at.present?
  end

  def revoke
    return if revoked?

    update!(revoked_at: Time.current)
    track_event "revoked"
  end

  # Recorded at most once a minute, so busy keys don't write on every request.
  def used_from(ip)
    return if last_used_at && last_used_at > LAST_USED_PRECISION.ago

    update_columns(last_used_at: Time.current, last_used_ip: ip)
  end

  private
    def generate_token
      @token = "#{PREFIX}#{SecureRandom.base58(40)}"
      self.token_digest = self.class.digest(@token)
      self.token_prefix = @token.first(10)
    end
end
