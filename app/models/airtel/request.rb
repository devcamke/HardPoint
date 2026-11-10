# A "pay with Airtel Money" prompt sent to a customer's phone from the till. Airtel calls back when the
# customer enters their PIN (or doesn't); since callbacks get lost, the till also asks Airtel.
class Airtel::Request < ApplicationRecord
  include AccountOwned, Monetary

  STATUS_CHECK_AFTER = 20.seconds
  EXPIRES_AFTER = 3.minutes
  PAID, IN_PROGRESS = "TS", %w[ TIP TA ] # TA: "ambiguous", still being settled; anything else has failed

  belongs_to :merchant
  belongs_to :sale
  belongs_to :payment, optional: true
  belongs_to :requested_by, class_name: "User", default: -> { Current.user }, optional: true

  enum :status, %w[ pending paid failed cancelled expired ].index_by(&:itself), default: :pending

  money_attribute :amount

  validates :phone, format: { with: /\A254[17]\d{8}\z/, message: "must be a mobile number like 0733 000 111" }
  validates :amount_cents, numericality: { greater_than_or_equal_to: 100 }
  validates_same_account :merchant, :sale

  before_validation(on: :create) { self.transaction_id ||= "HP#{SecureRandom.alphanumeric(14).upcase}" }

  scope :unused, -> { paid.where(payment_id: nil) }

  # The paid prompts a member may use at a till. Staff who see every branch may use any; staff bound to a branch
  # only those sent from this till, through their branch's merchant account or a shop-wide one.
  def self.usable_by(membership, at:)
    return all unless membership&.bound_to_branch?

    where(merchant_id: Airtel::Merchant.where(branch_id: [ membership.branch_id, nil ]).select(:id), sale_id: Sale.where(register_id: at.id).select(:id))
  end

  # Airtel Money takes whole shillings, so a due amount with cents is rounded up; the sale is only ever paid what's due.
  def whole_shillings
    (amount_cents / 100.0).ceil
  end

  def msisdn = phone.delete_prefix("254")

  def send_prompt
    merchant.client.request_payment(msisdn: msisdn, amount: whole_shillings, transaction_id: transaction_id,
      reference: "#{merchant.account.name.first(20)} #{sale.branch.code}")
  rescue Airtel::Client::Refused, JsonHttp::Unreachable => error
    update!(status: :failed, result_description: error.message, resolved_at: Time.current)
  end

  def resolve(status_code:, airtel_money_id: nil, message: nil)
    with_lock do
      if status_code == PAID
        # Money that arrives after the till stopped waiting is still money received: kept to use on a sale.
        return unless pending? || cancelled? || expired?

        waiting = pending?
        update!(status: :paid, result_code: status_code, result_description: message, airtel_money_id: airtel_money_id.presence || transaction_id, resolved_at: Time.current)
        pay_sale if waiting
      elsif pending? && !status_code.in?(IN_PROGRESS)
        update!(status: :failed, result_code: status_code, result_description: message.presence || "Not paid", resolved_at: Time.current)
      end
    end
  end

  # When the callback is late: ask Airtel, and give up after a few minutes.
  def check_status
    return unless pending? && created_at < STATUS_CHECK_AFTER.ago

    transaction = merchant.client.status(transaction_id)
    resolve(status_code: transaction["status"].to_s, airtel_money_id: transaction["airtel_money_id"], message: transaction["message"])
    update!(status: :expired, result_description: "No answer from the customer's phone", resolved_at: Time.current) if pending? && created_at < EXPIRES_AFTER.ago
  rescue Airtel::Client::Refused, JsonHttp::Unreachable
    update!(status: :expired, result_description: "No answer from Airtel", resolved_at: Time.current) if pending? && created_at < EXPIRES_AFTER.ago
  end

  def cancel
    pending? && update(status: :cancelled, result_description: "Cancelled at the till", resolved_at: Time.current)
  end

  # A paid prompt is money received even if the till gave up waiting: it can be used on a sale later.
  def use_on(sale)
    return unless paid? && payment.nil?

    taken = sale.pay(tender: "airtel_money", amount_cents: [ amount_cents, sale.balance_due_cents ].min, tendered_cents: amount_cents, reference: airtel_money_id)
    update!(payment: taken) if taken.persisted?
    taken
  end

  private
    def pay_sale
      return unless sale.open?

      Current.set(user: requested_by) { use_on(sale) }
    end
end
