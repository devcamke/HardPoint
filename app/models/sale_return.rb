# Goods brought back against a receipt. Refunds are worth what the customer actually paid for
# those items (their share of line and cart discounts included). Restocked items go back on the
# shelf; items not restocked (damaged) are simply written off.
class SaleReturn < ApplicationRecord
  include AccountOwned, Monetary

  REFUND_METHODS = %w[ cash card mobile_money on_account ].freeze

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

  before_validation(on: :create) { self.branch ||= sale&.branch }
  before_create :number_and_total
  after_create :restock_and_record
  after_create :take_back_points

  after_create_commit -> { account.refresh_dashboard_later }
  after_create_commit -> { sale.job&.touch }
  after_create_commit -> { Etims::Submission.queue(self, kind: "credit_note") }

  scope :chronologically, -> { order(created_at: :desc, id: :desc) }

  def return_number
    "#{branch.code}-R#{number.to_s.rjust(5, "0")}"
  end

  private
    def number_and_total
      self.number = DocumentSequence.next_number(branch, "return")
      lines.each(&:calculate_totals)
      self.total_cents = lines.sum(&:total_cents)
      self.tax_cents = lines.sum(&:tax_cents)
    end

    # The points the sale earned, in proportion to what came back.
    def take_back_points
      earned = sale.loyalty_entries.where(kind: "earned").sum(:points)
      return unless earned.positive? && sale.customer && sale.total_cents.positive?

      taken_back = -sale.loyalty_entries.where.not(sale_return_id: nil).sum(:points)
      points = [ (earned * total_cents.to_r / sale.total_cents).floor, earned - taken_back ].min
      sale.loyalty_entries.create!(account: account, customer: sale.customer, sale_return: self, kind: "reversed", points: -points, creator: creator) if points.positive?
    end

    def restock_and_record
      lines.select(&:restock?).each { |line| line.sale_line.restore_stock(line.quantity, source: self) }
      sale.track_event "returned", creator: creator, return_number: return_number, total: total_cents,
        refund_method: refund_method, approver: approver&.name
    end
end
