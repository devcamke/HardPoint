# A contractor's job or project: "Kamau residence, Kitengela". Sales and orders for the customer can
# be tagged with one of their open jobs, so the job shows what it has cost against its budget and
# what went into it, and the contractor can hand their own client a cost summary.
class Job < ApplicationRecord
  include AccountOwned, Eventable, Monetary
  tracks_lifecycle only: %i[ create update ]

  Material = Data.define(:product, :product_unit, :quantity, :total_cents) do
    def description = product_unit ? "#{product.name} (#{product_unit})" : product.name
    def unit = product_unit&.unit || product.unit
  end

  belongs_to :customer
  belongs_to :creator, class_name: "User", default: -> { Current.user }, optional: true
  has_many :sales, dependent: :restrict_with_error
  has_many :customer_orders, dependent: :restrict_with_error

  enum :status, %w[ open closed ].index_by(&:itself), default: "open"

  money_attribute :budget

  normalizes :name, with: ->(name) { name.squish }
  normalizes :reference, :site, with: ->(value) { value.squish.presence }

  validates :name, presence: true, length: { maximum: 100 }, uniqueness: { scope: :customer_id }
  validates :budget_cents, numericality: { greater_than: 0 }, allow_nil: true
  validates_same_account :customer

  scope :alphabetically, -> { order(:name) }
  scope :recent_first, -> { order(updated_at: :desc, id: :desc) }

  # Spend for many jobs at once, for lists: { job id => cents }.
  def self.spent_cents_by_id(ids)
    sold = Sale.completed.where(job_id: ids).group(:job_id).sum(:total_cents)
    returned = SaleReturn.joins(:sale).where(sales: { job_id: ids, status: "completed" }).group("sales.job_id").sum(:total_cents)
    ids.index_with { sold.fetch(_1, 0) - returned.fetch(_1, 0) }
  end

  # "Kamau residence (LPO 2291)", wherever a job is named on a document.
  def label
    reference ? "#{name} (#{reference})" : name
  end
  alias_method :event_name, :label

  def completed_sales
    sales.completed
  end

  def returns
    SaleReturn.joins(:sale).where(sales: { job_id: id, status: "completed" })
  end

  # What the job has cost: completed sales less what was returned from them.
  def spent_cents
    completed_sales.sum(:total_cents) - returns.sum(:total_cents)
  end

  def budget_left_cents
    budget_cents && budget_cents - spent_cents
  end

  def over_budget?
    budget_cents.present? && spent_cents > budget_cents
  end

  def budget_used_percent
    budget_cents && (spent_cents * 100.0 / budget_cents).round
  end

  # Everything that went into the job, product by product, net of returns; biggest spend first.
  def materials
    bought = SaleLine.joins(:sale).merge(completed_sales)
      .group(:product_id, :product_unit_id).pluck(:product_id, :product_unit_id, Arel.sql("SUM(sale_lines.quantity)"), Arel.sql("SUM(sale_lines.total_cents)"))
    returned = SaleReturnLine.joins(sale_line: :sale).merge(completed_sales)
      .group("sale_lines.product_id", "sale_lines.product_unit_id").pluck("sale_lines.product_id", "sale_lines.product_unit_id", Arel.sql("SUM(sale_return_lines.quantity)"), Arel.sql("SUM(sale_return_lines.total_cents)"))
      .to_h { |product_id, unit_id, quantity, total| [ [ product_id, unit_id ], [ quantity, total ] ] }

    products = account.products.includes(:unit).where(id: bought.map(&:first)).index_by(&:id)
    units = ProductUnit.includes(:unit).where(id: bought.map(&:second).compact).index_by(&:id)

    bought.filter_map do |product_id, unit_id, quantity, total|
      returned_quantity, returned_total = returned[[ product_id, unit_id ]] || [ 0, 0 ]
      next unless quantity - returned_quantity > 0
      Material.new(products[product_id], units[unit_id], quantity - returned_quantity, total - returned_total)
    end.sort_by { -_1.total_cents }
  end

  def close
    open? && update(status: "closed", closed_at: Time.current)
  end

  def reopen
    closed? && update(status: "open", closed_at: nil)
  end

  def tracked_changes
    super.except("closed_at")
  end
end
