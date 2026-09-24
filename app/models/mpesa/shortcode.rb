# A shop's Paybill or Till number with its Daraja credentials, kept encrypted. A branch can have
# its own Till; one without a branch serves every branch that doesn't.
class Mpesa::Shortcode < ApplicationRecord
  include AccountOwned, Eventable, Callbacks
  tracks_lifecycle

  ENVIRONMENTS = %w[ sandbox production simulator ].freeze
  TRANSACTION_TYPES = { "paybill" => "CustomerPayBillOnline", "buy_goods" => "CustomerBuyGoodsOnline" }.freeze

  belongs_to :branch, optional: true
  has_many :stk_requests, dependent: :restrict_with_error
  has_many :transactions, dependent: :restrict_with_error

  encrypts :consumer_key, :consumer_secret, :passkey
  has_secure_token :callback_token, length: 36

  normalizes :shortcode, :till_number, with: ->(number) { number.gsub(/\D/, "") }

  validates :name, presence: true
  validates :shortcode, format: { with: /\A\d{5,7}\z/, message: "must be the 5–7 digit Paybill or store number" }, uniqueness: { scope: :account_id }
  validates :till_number, format: { with: /\A\d{5,7}\z/ }, if: :buy_goods?
  validates :environment, inclusion: { in: ENVIRONMENTS }
  validates :transaction_type, inclusion: { in: TRANSACTION_TYPES.keys }
  validates :consumer_key, :consumer_secret, :passkey, presence: true, unless: :simulator?
  validate { errors.add :environment, "can't be the simulator on a live server" if simulator? && !self.class.simulator_allowed? }
  validates_same_account :branch

  scope :active, -> { where(active: true) }

  # The Till for a branch, or the shop-wide one.
  def self.for_branch(branch)
    active.where(branch_id: [ branch&.id, nil ]).order(Arel.sql("branch_id IS NULL"), :id).first
  end

  def self.simulator_allowed?
    !Rails.env.production? || ENV["ALLOW_INTEGRATION_SIMULATORS"].present?
  end

  def simulator? = environment == "simulator"
  def buy_goods? = transaction_type == "buy_goods"
  def daraja_transaction_type = TRANSACTION_TYPES.fetch(transaction_type)

  # Payments go to the Till number for Buy Goods; to the Paybill itself otherwise.
  def party_b
    buy_goods? ? till_number : shortcode
  end

  def label
    "#{buy_goods? ? "Till" : "Paybill"} #{party_b}"
  end

  def client
    Mpesa::Client.new(self)
  end

  def test_connection
    client.access_token.present?
  end

  def register_c2b_urls
    client.register_c2b_urls(confirmation_url: callback_url(:confirmation), validation_url: callback_url(:validation))
    update!(c2b_registered_at: Time.current)
    track_event "c2b_registered"
  end

  # Sends a "pay with M-Pesa" prompt to the customer's phone for (part of) a sale.
  def request_payment(sale:, phone:, amount_cents:)
    stk_requests.create!(account: account, sale: sale, phone: PhoneNumber.normalize(phone) || phone.to_s, amount_cents: amount_cents).tap(&:send_prompt)
  end

  def callback_url(kind)
    helpers = Rails.application.routes.url_helpers
    options = Rails.configuration.x.webhook_url_options

    case kind
    when :stk then helpers.mpesa_webhook_stk_url(callback_token, **options)
    when :confirmation then helpers.mpesa_webhook_confirmation_url(callback_token, **options)
    when :validation then helpers.mpesa_webhook_validation_url(callback_token, **options)
    end
  end
end
