# A shop's Airtel Money merchant account with its Open API credentials, kept encrypted. A branch can have its
# own; one without a branch serves every branch that doesn't. Airtel calls back to the address with this
# merchant's secret token, which the shop enters once in Airtel's developer portal.
class Airtel::Merchant < ApplicationRecord
  include AccountOwned, Eventable
  tracks_lifecycle

  ENVIRONMENTS = %w[ sandbox production simulator ].freeze

  belongs_to :branch, optional: true
  has_many :requests, dependent: :restrict_with_error

  encrypts :client_id, :client_secret
  has_secure_token :callback_token, length: 36

  normalizes :merchant_number, with: ->(number) { number.gsub(/\D/, "").presence }

  validates :name, presence: true
  validates :environment, inclusion: { in: ENVIRONMENTS }
  validates :client_id, :client_secret, presence: true, unless: :simulator?
  validate { errors.add :environment, "can't be the simulator on a live server" if simulator? && !Mpesa::Shortcode.simulator_allowed? }
  validates_same_account :branch

  scope :active, -> { where(active: true) }

  def self.for_branch(branch)
    active.where(branch_id: [ branch&.id, nil ]).order(Arel.sql("branch_id IS NULL"), :id).first
  end

  def simulator? = environment == "simulator"

  def label
    merchant_number ? "Airtel Money #{merchant_number}" : "Airtel Money"
  end

  def client
    Airtel::Client.new(self)
  end

  def test_connection
    client.access_token.present?
  end

  # Sends a "pay with Airtel Money" prompt to the customer's phone for (part of) a sale.
  def request_payment(sale:, phone:, amount_cents:)
    requests.create!(account: account, sale: sale, phone: PhoneNumber.normalize(phone) || phone.to_s, amount_cents: amount_cents).tap(&:send_prompt)
  end

  # Airtel's callback for a prompt; safe to receive more than once.
  def receive_callback(payload)
    transaction = payload["transaction"] or return
    request = requests.find_by(transaction_id: transaction["id"].to_s) or return
    request.resolve(status_code: transaction["status_code"].to_s, airtel_money_id: transaction["airtel_money_id"], message: transaction["message"])
  end

  def callback_url
    Rails.application.routes.url_helpers.airtel_webhook_url(callback_token, **Rails.configuration.x.webhook_url_options)
  end
end
