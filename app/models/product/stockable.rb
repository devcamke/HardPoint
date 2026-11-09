# Stock is an append-only ledger of movements; stock_levels caches each branch's balance and is
# updated in the same transaction, under a row lock, so balances are always explainable.
module Product::Stockable
  extend ActiveSupport::Concern

  included do
    has_many :stock_levels, dependent: :destroy
    has_many :stock_movements, dependent: :restrict_with_error
    has_many :stock_batches, dependent: :restrict_with_error

    # Products at or below their reorder level at a branch. A branch carries a product once it has
    # had stock of it; products never stocked anywhere yet count as low everywhere, so they get ordered.
    scope :below_reorder_level_at, ->(branch) do
      where(track_stock: true).where("products.reorder_level > 0")
        .joins(sanitize_sql_array([ "LEFT JOIN stock_levels ON stock_levels.product_id = products.id AND stock_levels.branch_id = ?", branch&.id ]))
        .where("stock_levels.id IS NOT NULL OR NOT EXISTS (SELECT 1 FROM stock_levels carried WHERE carried.product_id = products.id)")
        .where("COALESCE(stock_levels.quantity, 0) <= products.reorder_level")
    end
  end

  def stock_at(branch)
    return kit_stock_at(branch) if kit?

    stock_levels.find_by(branch: branch)&.quantity || 0
  end

  def stock_on_hand
    stock_levels.sum(:quantity)
  end

  # Stock at a branch promised to confirmed orders not yet collected (quotes promise nothing), in the base unit.
  # `except` leaves out one order: the one being collected at the till, whose own stock isn't "someone else's".
  def reserved_at(branch, except: nil)
    lines = CustomerOrderLine.joins(:customer_order).where(product_id: id, customer_orders: { branch_id: branch.id, status: %w[ ordered ready ] })
    lines = lines.where.not(customer_order_id: except.id) if except
    lines.left_joins(:product_unit).sum("GREATEST(customer_order_lines.quantity - customer_order_lines.collected_quantity, 0) * COALESCE(product_units.quantity, 1)")
  end

  # What can be sold or promised to a new customer at a branch: on hand, less what's promised already.
  def available_at(branch, except: nil)
    stock_at(branch) - reserved_at(branch, except: except)
  end

  def below_reorder_level_at?(branch)
    reorder_level.positive? && stock_at(branch) <= reorder_level
  end

  # Movements that must never take expired stock: a customer mustn't be sold it, and another branch mustn't
  # be sent it. Counts, corrections and write-offs may take it, since that's how it leaves.
  IN_DATE_ONLY = %w[ sold transfer_out ].freeze

  # For products tracked by batch, stock in goes to the batch given (a delivery), or back to the
  # batches it came from (a void, a return, a transfer arriving); stock out comes from the batch
  # given (a write-off) or first-expiring-first, skipping expired batches: a sale or transfer that
  # would need them raises Product::ExpiredStock, other movements fall through to them when nothing
  # else is left. Each batch touched gets its own ledger line.
  def move_stock(branch:, quantity:, reason:, source: nil, note: nil, unit_cost_cents: cost_cents, creator: Current.user, batch: nil, reverses: nil, allow_expired: nil)
    raise ArgumentError, "#{name} doesn't track stock" unless track_stock?
    allow_expired = !reason.to_s.in?(IN_DATE_ONLY) if allow_expired.nil?

    transaction do
      level = stock_levels.create_or_find_by!(account: account, branch: branch)
      level.lock!

      portions = tracks_batches? ? Product::Batching.new(self, branch).portions(quantity.to_d, batch: batch, reverses: reverses, allow_expired: allow_expired) : [ [ nil, quantity.to_d ] ]
      portions.map do |stock_batch, amount|
        stock_batch&.update!(quantity: stock_batch.quantity + amount)
        level.update! quantity: level.quantity + amount

        stock_movements.create! account: account, branch: branch, quantity: amount, balance: level.quantity, stock_batch: stock_batch,
          reason: reason, source: source, note: note, unit_cost_cents: unit_cost_cents, creator: creator
      end.last
    end
  end

  # Stock at a branch that isn't in any batch: from before batches were tracked, or counted in.
  def unbatched_stock_at(branch)
    stock_at(branch) - stock_batches.where(branch: branch).sum(:quantity)
  end

  # Stock at a branch that can be sold or sent on: everything, less what's sitting in expired batches.
  def in_date_stock_at(branch)
    return stock_at(branch) unless tracks_batches?

    stock_at(branch) - stock_batches.where(branch: branch).in_stock.expired.sum(:quantity)
  end

  private
    # A kit is in stock as many times as its scarcest component allows.
    def kit_stock_at(branch)
      kit_components.includes(:component).map do |part|
        (part.component.stock_at(branch) / part.quantity).floor
      end.min || 0
    end
end
