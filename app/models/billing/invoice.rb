class Billing::Invoice < ApplicationRecord
  include AccountOwned, Monetary

  has_many :payments, dependent: :destroy

  enum :status, %w[ open paid void ].index_by(&:itself), default: :open

  money_attribute :amount

  validates :plan, :period_start, :period_end, :due_on, presence: true
  validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }

  before_validation(on: :create) do
    self.number ||= "HP-#{Date.current.year}-#{self.class.connection.select_value("SELECT nextval('billing_invoice_numbers')").to_s.rjust(6, "0")}"
  end

  scope :chronologically, -> { order(period_start: :desc, id: :desc) }

  def plan_name
    Plan.find(plan).name
  end

  def description
    "#{plan_name} plan, #{period_start.to_fs(:long)} to #{(period_end - 1).to_fs(:long)}"
  end

  def overdue?(on = Date.current)
    open? && due_on < on
  end

  def mark_paid(payment)
    with_lock do
      return false unless open?

      update!(status: :paid, paid_at: payment.completed_at || Time.current)
    end
    account.subscription_paid(self)
    BillingMailer.with(invoice: self, payment: payment).payment_received.deliver_later
    true
  end
end
