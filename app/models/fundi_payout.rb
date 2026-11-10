# Commission paid out to a fundi, by an owner or manager: cash from a till's drawer (a till payout, so the drawer
# still balances and the profit and loss counts it as an expense), or M-Pesa with its transaction code.
class FundiPayout < ApplicationRecord
  include AccountOwned, Eventable, Monetary

  METHODS = { "cash" => "Cash from a till", "mobile_money" => "M-Pesa" }.freeze

  belongs_to :fundi
  belongs_to :cash_movement, optional: true
  belongs_to :paid_by, class_name: "User", default: -> { Current.user }

  attr_accessor :shift

  money_attribute :amount

  normalizes :reference, with: ->(reference) { reference.strip.upcase.presence }

  validates :payment_method, inclusion: { in: METHODS.keys }
  validates :amount_cents, numericality: { greater_than: 0 }
  validates :reference, presence: { message: "can't be blank: enter the M-Pesa code" }, if: -> { payment_method == "mobile_money" }
  validates_same_account :fundi
  validate :not_more_than_owed
  validate :from_an_open_till, if: -> { payment_method == "cash" }

  before_create :take_from_drawer, if: -> { payment_method == "cash" }
  after_create :record_in_ledger

  def method_name = METHODS.fetch(payment_method)

  private
    def not_more_than_owed
      owed = fundi&.balance_cents.to_i
      errors.add :amount, "is more than the #{Money.format(owed)} #{fundi.name} is owed" if fundi && amount_cents.to_i > owed
    end

    def from_an_open_till
      errors.add :base, "Choose the till the cash comes from" unless shift&.open? && shift.account_id == account_id
    end

    def take_from_drawer
      self.cash_movement = shift.cash_movements.create!(account: account, kind: "payout", amount_cents: amount_cents,
        reason: "Commission to #{fundi.name}", creator: paid_by)
    end

    def record_in_ledger
      fundi.entries.create!(account: account, kind: "paid", amount_cents: -amount_cents, source: self, creator: paid_by)
      track_event "paid", fundi: fundi.name, amount: amount_cents, payment_method: payment_method, reference: reference
    end
end
