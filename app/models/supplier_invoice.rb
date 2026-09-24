class SupplierInvoice < ApplicationRecord
  include AccountOwned, Eventable, Monetary

  belongs_to :supplier
  belongs_to :goods_receipt, optional: true
  belongs_to :creator, class_name: "User", default: -> { Current.user }, optional: true

  money_attribute :total, :tax

  normalizes :number, with: ->(number) { number.strip.upcase }

  validates :number, presence: true, uniqueness: { scope: :supplier_id, message: "has already been recorded for this supplier" }
  validates :invoice_date, :due_date, presence: true
  validates :total_cents, numericality: { greater_than: 0 }
  validates :tax_cents, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: :total_cents }
  validates_same_account :supplier, :goods_receipt
  validate { errors.add :goods_receipt, "is from another supplier" if goods_receipt && goods_receipt.supplier_id != supplier_id }

  before_validation { self.due_date ||= invoice_date + supplier.payment_terms_days.days if invoice_date && supplier }
  after_create { track_event "recorded", supplier: supplier.name, total: total_cents }

  scope :chronologically, -> { order(invoice_date: :desc, id: :desc) }

  def name
    "#{supplier.name} #{number}"
  end
end
