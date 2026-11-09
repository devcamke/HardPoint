class SupplierInvoice < ApplicationRecord
  include AccountOwned, Eventable, Monetary

  belongs_to :supplier
  belongs_to :goods_receipt, optional: true
  belongs_to :creator, class_name: "User", default: -> { Current.user }, optional: true

  money_attribute :total, :tax

  normalizes :number, with: ->(number) { number.strip.upcase }

  validates :number, presence: true, uniqueness: { scope: :supplier_id, message: "has already been recorded for this supplier" }
  validates :goods_receipt_id, uniqueness: { message: "already has an invoice recorded against it" }, allow_nil: true
  validates :invoice_date, :due_date, presence: true
  validates :total_cents, numericality: { greater_than: 0 }
  validates :tax_cents, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: :total_cents }
  validates_same_account :supplier, :goods_receipt
  validate { errors.add :goods_receipt, "is from another supplier" if goods_receipt && goods_receipt.supplier_id != supplier_id }

  before_validation { self.due_date ||= invoice_date + supplier.payment_terms_days.days if invoice_date && supplier }
  before_validation(on: :create) { self.exchange_rate ||= goods_receipt&.exchange_rate || supplier&.current_rate }
  after_create { track_event "recorded", supplier: supplier.name, total: total_cents }

  scope :chronologically, -> { order(invoice_date: :desc, id: :desc) }

  def name
    "#{supplier.name} #{number}"
  end

  # An invoice is checked against its delivery's goods: both ex tax, both in the supplier's currency.
  # Transport and duty on the delivery were paid here, so they aren't the supplier's to invoice.
  # A small difference (rounding, a few cents a unit) is let through without a word.
  VARIANCE_TOLERANCE = BigDecimal("0.01")

  def variance_cents
    goods_receipt ? (total_cents - tax_cents) - goods_receipt.goods_value_cents : 0
  end

  def variance?
    goods_receipt.present? && variance_cents.abs > goods_receipt.goods_value_cents * VARIANCE_TOLERANCE
  end

  # "KES 3,000.00 more than the goods on MAIN-GRN00001"
  def variance_description
    "#{Money.format(variance_cents.abs, currency: supplier.currency_code)} #{variance_cents.positive? ? "more" : "less"} than the goods on #{goods_receipt.reference}"
  end
end
