# Goods brought back against a receipt. Refunds are worth what the customer actually paid for
# those items (their share of line and cart discounts included), less any promotion the goods they
# keep no longer earn (SaleReturnLine.price). Restocked items go back on the
# shelf of the branch taking them back, which need not be the one that sold them; the return is
# numbered there and a cash refund comes from that till's drawer. Money is only refunded as money
# the customer actually handed over: the part of a sale put on account is refunded to the account.
class SaleReturn < ApplicationRecord
  include AccountOwned, Monetary

  REFUND_METHODS = %w[ cash card mobile_money airtel_money on_account ].freeze

  belongs_to :sale
  belongs_to :branch
  belongs_to :shift
  belongs_to :creator, class_name: "User", default: -> { Current.user }
  belongs_to :approver, class_name: "User", optional: true
  has_many :lines, class_name: "SaleReturnLine", dependent: :destroy, inverse_of: :sale_return

  money_attribute :total, :tax

  accepts_nested_attributes_for :lines, reject_if: ->(attributes) { attributes["quantity"].to_d.zero? }

  validates :refund_method, inclusion: { in: REFUND_METHODS }
  validates_same_account :sale, :shift
  validate { errors.add :sale, "must be a completed sale" unless sale&.completed? }
  validate { errors.add :base, "Choose at least one item to return" if lines.empty? }
  validate { errors.add :shift, "must be open" if shift&.closed? }
  validate { errors.add :refund_method, "on account needs the sale to have a customer" if refund_method == "on_account" && sale&.customer.nil? }
  validate :only_money_paid_is_refunded_as_money, on: :create

  before_validation(on: :create) { self.branch ||= shift&.branch || sale&.branch }
  # Saving validates inside the save's transaction; holding the sale's row until it commits means a
  # second return (or a void) of the same sale waits, then counts what this one took back.
  before_validation(on: :create) { Sale.where(id: sale_id).lock.pick(:id) if sale_id }
  before_create :number_and_total
  after_create :restock_and_record

  after_create_commit -> { account.refresh_dashboard_later }
  after_create_commit -> { sale.job&.touch }
  after_create_commit -> { Etims::Submission.queue(self, kind: "credit_note") }

  scope :chronologically, -> { order(created_at: :desc, id: :desc) }

  def return_number
    "#{branch.code}-R#{number.to_s.rjust(5, "0")}"
  end

  MONEY_TENDERS = (Payment::TENDERS - %w[ on_account ]).freeze

  # What the customer paid in money (cash, card, phone, deposit) less what has already been refunded as money.
  # A sale put on account hasn't been paid for yet, so handing cash back for it would pay the customer twice.
  def self.money_refundable_cents(sale)
    paid = sale.payments.select { _1.persisted? && _1.tender.in?(MONEY_TENDERS) }.sum(&:amount_cents)
    paid - sale.sale_returns.where.not(refund_method: "on_account").sum(:total_cents)
  end

  private
    def only_money_paid_is_refunded_as_money
      return unless sale&.completed? && refund_method.present? && refund_method != "on_account"

      SaleReturnLine.price(lines, sale)
      refundable = self.class.money_refundable_cents(sale)
      if lines.sum(&:total_cents) > refundable
        errors.add :refund_method, refundable.positive? ?
          "can refund at most #{Money.format(refundable)} in money: the rest of this sale was put on account, so refund that part to the customer's account" :
          "can't be money: this sale was put on account and hasn't been paid, so credit the customer's account instead"
      end
    end

    def number_and_total
      self.number = DocumentSequence.next_number(branch, "return")
      SaleReturnLine.price(lines, sale)
      self.total_cents = lines.sum(&:total_cents)
      self.tax_cents = lines.sum(&:tax_cents)
    end

    def restock_and_record
      lines.select(&:restock?).each { |line| line.sale_line.restore_stock(line.quantity, source: self, branch: branch) }
      sale.track_event "returned", creator: creator, return_number: return_number, total: total_cents,
        refund_method: refund_method, approver: approver
    end
end
