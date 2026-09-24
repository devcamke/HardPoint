# A stock take. Starting one snapshots what the system expects at the branch (for everything,
# or one category for a cycle count). Staff record what they actually count; a manager approves,
# and the differences are posted to the ledger. Differences are measured against the snapshot,
# so sales during the count don't distort them.
class StockCount < ApplicationRecord
  include AccountOwned, Eventable

  belongs_to :branch
  belongs_to :category, optional: true
  belongs_to :creator, class_name: "User", default: -> { Current.user }, optional: true
  belongs_to :approver, class_name: "User", optional: true
  has_many :lines, class_name: "StockCountLine", dependent: :delete_all

  enum :status, %w[ counting submitted approved cancelled ].index_by(&:itself), default: :counting

  validates_same_account :branch, :category

  after_create :snapshot_expected_stock
  scope :chronologically, -> { order(created_at: :desc, id: :desc) }

  def name
    "#{branch.name} · #{category&.name || "all products"} · #{created_at.to_date.to_fs(:long)}"
  end

  def submit
    counting? && update(status: :submitted, submitted_at: Time.current)
  end

  def approve(user = Current.user)
    with_lock do
      return false unless submitted?

      lines.counted.includes(:product).each do |line|
        next if line.variance.zero?
        line.product.move_stock(branch: branch, quantity: line.variance, reason: "count", source: self, creator: user)
      end

      update! status: :approved, approver: user, approved_at: Time.current
      track_event "approved", adjusted_lines: lines.counted.with_variance.count
    end
  end

  def cancel
    (counting? || submitted?) && update(status: :cancelled)
  end

  def progress
    [ lines.counted.count, lines.count ]
  end

  def variance_value_cents
    lines.counted.joins(:product).sum("(stock_count_lines.counted_quantity - stock_count_lines.expected_quantity) * products.cost_cents").round
  end

  private
    def snapshot_expected_stock
      products = account.products.active.where(track_stock: true)
      products = products.where(category: category) if category
      levels = StockLevel.where(branch: branch).pluck(:product_id, :quantity).to_h
      now = Time.current

      rows = products.pluck(:id).map do |product_id|
        { account_id: account_id, stock_count_id: id, product_id: product_id, expected_quantity: levels.fetch(product_id, 0), created_at: now, updated_at: now }
      end
      StockCountLine.insert_all(rows) if rows.any?

      track_event "started"
    end
end
