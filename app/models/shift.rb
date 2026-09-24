# A cashier's session at a till, from opening float to the closing count. The drawer should hold
# the float plus cash taken, less cash refunded, paid out or dropped to the safe; the count at
# close is "blind" (the cashier isn't shown the expected figure) and the difference is the variance.
class Shift < ApplicationRecord
  include AccountOwned, Eventable, Monetary

  belongs_to :branch
  belongs_to :register
  belongs_to :opened_by, class_name: "User", default: -> { Current.user }
  belongs_to :closed_by, class_name: "User", optional: true
  has_many :sales, dependent: :restrict_with_error
  has_many :cash_movements, dependent: :destroy
  has_many :sale_returns, dependent: :restrict_with_error
  has_many :deposits, dependent: :restrict_with_error
  has_many :customer_payments, dependent: :restrict_with_error

  enum :status, %w[ open closed ].index_by(&:itself), default: :open

  money_attribute :opening_float, :expected_cash, :counted_cash

  validates :opening_float_cents, numericality: { greater_than_or_equal_to: 0 }
  validates_same_account :register
  validate :one_open_shift_per_till, on: :create

  before_validation(on: :create) { self.branch ||= register&.branch; self.opened_at ||= Time.current }
  after_create { track_event "opened", opening_float: opening_float_cents }

  after_commit -> { account.refresh_dashboard_later }, if: -> { saved_change_to_status? || previously_new_record? }

  scope :chronologically, -> { order(opened_at: :desc, id: :desc) }

  def name
    "#{register.name} · #{opened_at.to_date.to_fs(:long)}"
  end

  def current_sale
    sales.find_by(status: "open") || sales.create!(account: account, branch: branch, register: register)
  end

  def cash_sales_cents
    Payment.cash.joins(:sale).where(sales: { shift_id: id, status: "completed" }).sum(:amount_cents)
  end

  def cash_refunds_cents
    sale_returns.where(refund_method: "cash").sum(:total_cents)
  end

  # Deposits on orders (less deposits refunded) and account payments, taken in cash.
  def cash_deposits_cents
    deposits.cash.sum(:amount_cents)
  end

  def cash_account_payments_cents
    customer_payments.cash.sum(:amount_cents)
  end

  def cash_movement_totals
    cash_movements.group(:kind).sum(:amount_cents)
  end

  def expected_cash_cents_now
    movements = cash_movement_totals
    opening_float_cents + cash_sales_cents - cash_refunds_cents + cash_deposits_cents + cash_account_payments_cents +
      movements.fetch("pay_in", 0) - movements.fetch("payout", 0) - movements.fetch("drop", 0)
  end

  def variance_cents
    counted_cash_cents - expected_cash_cents if closed?
  end

  def unfinished_sales
    sales.where(status: %w[ open parked ]).where(id: SaleLine.select(:sale_id))
  end

  def close(counted_cash_cents:, by: Current.user, note: nil)
    with_lock do
      return false unless open?

      if unfinished_sales.any?
        errors.add :base, "Finish or discard the sales still open or parked on this till first"
        return false
      end

      sales.where(status: %w[ open parked ]).destroy_all
      update! status: :closed, closed_by: by, closed_at: Time.current, note: note,
        expected_cash_cents: expected_cash_cents_now, counted_cash_cents: counted_cash_cents
      track_event "closed", expected: expected_cash_cents, counted: counted_cash_cents, variance: variance_cents
    end
  end

  def report
    ShiftReport.new(self)
  end

  private
    def one_open_shift_per_till
      errors.add :register, "already has an open shift" if register && register.shifts.open.exists?
    end
end
