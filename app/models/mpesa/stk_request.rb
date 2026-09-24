# A "pay with M-Pesa" prompt sent to a customer's phone from the till. Safaricom calls back when
# the customer enters their PIN (or cancels); if no callback comes, the till asks Safaricom.
class Mpesa::StkRequest < ApplicationRecord
  include AccountOwned, Monetary

  STATUS_CHECK_AFTER = 30.seconds
  EXPIRES_AFTER = 3.minutes

  belongs_to :shortcode
  belongs_to :sale
  belongs_to :payment, optional: true
  belongs_to :requested_by, class_name: "User", default: -> { Current.user }, optional: true

  enum :status, %w[ pending paid failed cancelled expired ].index_by(&:itself), default: :pending

  money_attribute :amount

  validates :phone, format: { with: /\A254[17]\d{8}\z/, message: "must be a Safaricom number like 0722 000 111" }
  validates :amount_cents, numericality: { greater_than_or_equal_to: 100 }
  validates_same_account :shortcode, :sale

  # M-Pesa takes whole shillings, so a due amount with cents is rounded up; the sale is only
  # ever paid what's due.
  def whole_shillings
    (amount_cents / 100.0).ceil
  end

  def send_prompt
    response = shortcode.client.stk_push(phone: phone, amount: whole_shillings, reference: sale.branch.code,
      description: "#{shortcode.account.name.first(8)} sale", callback_url: shortcode.callback_url(:stk))
    update!(merchant_request_id: response["MerchantRequestID"], checkout_request_id: response["CheckoutRequestID"])
  rescue Mpesa::Client::Refused, JsonHttp::Unreachable => error
    update!(status: :failed, result_description: error.message, resolved_at: Time.current)
  end

  def resolve(result_code:, description: nil, receipt_number: nil, amount_cents: nil, phone: nil, transacted_at: nil, payload: {})
    with_lock do
      if result_code == "0"
        transaction = record_transaction(receipt_number, amount_cents || self.amount_cents, phone, transacted_at, payload)
        if pending?
          update!(status: :paid, result_code: result_code, result_description: description, receipt_number: transaction.trans_id, resolved_at: Time.current)
          pay_sale(transaction)
        end
      elsif pending?
        update!(status: result_code == "1032" ? :cancelled : :failed, result_code: result_code, result_description: description, resolved_at: Time.current)
      end
    end
  end

  # When the callback is late: ask Safaricom, and give up after a few minutes.
  def check_status
    return unless pending? && checkout_request_id && created_at < STATUS_CHECK_AFTER.ago

    body = shortcode.client.stk_query(checkout_request_id)
    if body["ResultCode"].present?
      resolve(result_code: body["ResultCode"].to_s, description: body["ResultDesc"])
    elsif created_at < EXPIRES_AFTER.ago
      update!(status: :expired, result_description: "No answer from the customer's phone", resolved_at: Time.current)
    end
  rescue Mpesa::Client::Refused, JsonHttp::Unreachable
    update!(status: :expired, result_description: "No answer from Safaricom", resolved_at: Time.current) if created_at < EXPIRES_AFTER.ago
  end

  def cancel
    pending? && update(status: :cancelled, result_description: "Cancelled at the till", resolved_at: Time.current)
  end

  private
    # A paid prompt is money received even if the till gave up waiting, so it's always recorded.
    # A status check says "paid" without a receipt number; the checkout ID stands in for it.
    def record_transaction(receipt_number, amount_cents, phone, transacted_at, payload)
      Mpesa::Transaction.record(shortcode, source: "stk", trans_id: receipt_number || "STK#{checkout_request_id.last(10)}",
        amount_cents: amount_cents, phone: phone || self.phone, transacted_at: transacted_at || Time.current, payload: payload)
    end

    def pay_sale(transaction)
      return unless sale.open? && transaction.matched.nil?

      Current.set(user: requested_by) do
        payment = sale.pay(tender: "mobile_money", amount_cents: [ transaction.amount_cents, sale.balance_due_cents ].min, reference: transaction.trans_id)
        if payment.persisted?
          update!(payment: payment)
          transaction.match(payment)
        end
      end
    end
end
