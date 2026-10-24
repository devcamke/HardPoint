# A stock take. Starting one snapshots what the system expects at the branch (for everything,
# or one category for a cycle count). Staff record what they actually count; a manager approves,
# and the differences are posted to the ledger. Differences are measured against the snapshot,
# so sales during the count don't distort them. Batch-tracked products are counted batch by batch.
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

      lines.counted.includes(:product, batch_counts: :stock_batch).each do |line|
        if line.by_batch?
          line.batch_counts.each { _1.post_variance(self, user) }
        elsif line.variance.nonzero?
          line.product.move_stock(branch: branch, quantity: line.variance, reason: "count", source: self, creator: user)
        end
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
      snapshot_batches(products.where(tracks_batches: true), levels, now)

      track_event "started"
    end

    # A row for each batch in stock, and one for stock not in a batch (what the level holds beyond the batches).
    def snapshot_batches(products, levels, now)
      line_ids = lines.where(product_id: products.select(:id)).pluck(:product_id, :id).to_h
      return if line_ids.empty?

      batches = StockBatch.where(branch: branch, product_id: line_ids.keys).in_stock.group_by(&:product_id)
      rows = line_ids.flat_map do |product_id, line_id|
        in_batches = batches.fetch(product_id, [])
        unbatched = levels.fetch(product_id, 0) - in_batches.sum(&:quantity)
        [ *in_batches.map { { stock_batch_id: _1.id, number: _1.number, expires_on: _1.expires_on, expected_quantity: _1.quantity } },
          { stock_batch_id: nil, number: nil, expires_on: nil, expected_quantity: unbatched } ]
          .map { _1.merge(account_id: account_id, stock_count_line_id: line_id, created_at: now, updated_at: now) }
      end
      StockCountBatch.insert_all(rows)
    end
end
