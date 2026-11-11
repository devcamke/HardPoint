# Money Safaricom says arrived, and what it was matched to: a sale's payment, a deposit on an
# order, or a payment on account. Each M-Pesa transaction ID is recorded once, however many
# times Safaricom sends it.
class Mpesa::Transaction < ApplicationRecord
  include AccountOwned, Monetary

  SOURCES = %w[ stk c2b ].freeze
  RECENT = 3.hours

  belongs_to :shortcode
  belongs_to :matched, polymorphic: true, optional: true

  money_attribute :amount

  normalizes :trans_id, with: ->(id) { id.strip.upcase }

  validates :source, inclusion: { in: SOURCES }
  validates :trans_id, presence: true
  validates :amount_cents, numericality: { greater_than: 0 }

  scope :unmatched, -> { where(matched_id: nil) }
  scope :recent, -> { where(transacted_at: RECENT.ago..).order(transacted_at: :desc) }

  # The payments a member may use at a till. Staff who see every branch may use any. Staff bound to a branch use
  # payments to their branch's own Till or a shop-wide one, and a prompt's payment only at the till that sent it.
  def self.usable_by(membership, at:)
    return all unless membership&.bound_to_branch?

    prompts = Mpesa::StkRequest.joins(:sale).where(sales: { register_id: at.id })
    prompted_here = where("mpesa_transactions.payload #>> '{Body,stkCallback,CheckoutRequestID}' IN (#{prompts.select(:checkout_request_id).to_sql})")
      .or(where(trans_id: prompts.where.not(receipt_number: nil).select(:receipt_number)))

    where(shortcode_id: Mpesa::Shortcode.where(branch_id: [ membership.branch_id, nil ]).select(:id))
      .and(where.not(source: "stk").or(where(source: "stk").and(prompted_here)))
  end

  def self.record(shortcode, **attributes)
    shortcode.transactions.create_or_find_by!(account: shortcode.account, trans_id: attributes[:trans_id].to_s.strip.upcase) do |transaction|
      transaction.assign_attributes(attributes.except(:trans_id))
    end
  end

  def match(record)
    update!(matched: record, matched_at: Time.current)
  end

  # Payments to the Paybill carry the account number the customer typed: an order reference
  # makes a deposit, a customer's phone number pays their account. A code a cashier already typed
  # at the till is matched to that payment.
  def auto_match
    return if matched

    if (recorded = already_recorded)
      match(recorded)
    elsif (order = account.customer_orders.find_by_reference(bill_reference)) && order.takes_deposits?
      deposit = order.take_deposit(amount_cents: amount_cents, tender: "mobile_money", reference: trans_id)
      match(deposit) if deposit.persisted?
    elsif (customer = account.customers.find_by_account_number(bill_reference))
      # Refused (say the code was already used another way), the money stays on the list to be picked by hand.
      payment = customer.customer_payments.create(account: account, amount_cents: amount_cents, payment_method: "mobile_money", reference: trans_id,
        paid_on: transacted_at.to_date, note: "Paid to #{shortcode.label}", creator: nil)
      match(payment) if payment.persisted?
    end
  end

  # A cashier picks this payment from the list at the till.
  def attach_to(sale)
    with_lock do
      raise ArgumentError, "This M-Pesa payment has already been used" if matched

      payment = sale.pay(tender: "mobile_money", amount_cents: [ amount_cents, sale.balance_due_cents ].min, tendered_cents: amount_cents, reference: trans_id)
      match(payment) if payment.persisted?
      payment
    end
  end

  def payer
    [ payer_name, PhoneNumber.display(phone) ].compact_blank.join(" · ").presence || "Unknown"
  end

  private
    # Codes are typed as they come (" qwe12abc"), so they're compared the way MobileMoneyCode compares them.
    def already_recorded
      matching = ->(scope) { scope.where("upper(trim(reference)) = ?", trans_id).first }
      matching.(Payment.where(account: account).mobile_money) ||
        matching.(account.deposits.where(tender: "mobile_money")) ||
        matching.(account.customer_payments.where(payment_method: "mobile_money"))
    end
end
