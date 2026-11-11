# Stock is an append-only ledger of movements; stock_levels caches each branch's balance and is
# updated in the same transaction, under a row lock, so balances are always explainable.
module Product::Stockable
  extend ActiveSupport::Concern

  included do
    has_many :stock_levels, dependent: :destroy
    has_many :stock_movements, dependent: :restrict_with_error
    has_many :stock_refusals, dependent: :delete_all
    has_many :material_products, dependent: :delete_all
    has_many :stock_batches, dependent: :restrict_with_error

    # Products at or below their reorder level at a branch: the branch's own level where it has set
    # one, else the product's. A branch carries a product once it has had stock of it; products never
    # stocked anywhere yet count as low everywhere, so they get ordered.
    scope :below_reorder_level_at, ->(branch) do
      where(track_stock: true)
        .joins(sanitize_sql_array([ "LEFT JOIN stock_levels ON stock_levels.product_id = products.id AND stock_levels.branch_id = ?", branch&.id ]))
        .where("#{BRANCH_REORDER_LEVEL} > 0")
        .where("stock_levels.id IS NOT NULL OR NOT EXISTS (SELECT 1 FROM stock_levels carried WHERE carried.product_id = products.id)")
        .where("COALESCE(stock_levels.quantity, 0) <= #{BRANCH_REORDER_LEVEL}")
    end

    # At nothing (or less) where the branch carries it, with no reorder level to put it on the reorder list: it would
    # otherwise run out unnoticed, and the till can't sell it.
    scope :out_of_stock_unwatched_at, ->(branch) do
      where(track_stock: true, kit: false)
        .joins(sanitize_sql_array([ "JOIN stock_levels ON stock_levels.product_id = products.id AND stock_levels.branch_id = ?", branch&.id ]))
        .where("stock_levels.quantity <= 0").where("#{BRANCH_REORDER_LEVEL} <= 0")
    end

    # For lists of what's low, after below_reorder_level_at: the branch's quantity and reorder level
    # as columns (stock_quantity, branch_reorder_level), the furthest below first.
    scope :most_short_first, -> do
      select("products.*, COALESCE(stock_levels.quantity, 0) AS stock_quantity, #{BRANCH_REORDER_LEVEL} AS branch_reorder_level")
        .order(Arel.sql("COALESCE(stock_levels.quantity, 0) - #{BRANCH_REORDER_LEVEL}"))
    end
  end

  BRANCH_REORDER_LEVEL = "COALESCE(stock_levels.reorder_level, products.reorder_level)".freeze

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

  # The confirmed orders holding some of this product at a branch, oldest first.
  def orders_holding(branch, except: nil)
    lines = CustomerOrderLine.where(product_id: id).where("customer_order_lines.quantity > customer_order_lines.collected_quantity")
    orders = CustomerOrder.where(branch_id: branch.id, status: %w[ ordered ready ], id: lines.select(:customer_order_id))
    (except ? orders.where.not(id: except.id) : orders).order(:created_at, :id)
  end

  # What can be sold or promised to a new customer at a branch: on hand, less what's promised already.
  def available_at(branch, except: nil)
    stock_at(branch) - reserved_at(branch, except: except)
  end

  # A branch can set its own reorder level for a product; otherwise the product's applies everywhere.
  def reorder_level_at(branch)
    stock_levels.find_by(branch: branch)&.reorder_level || reorder_level
  end

  def below_reorder_level_at?(branch)
    level = reorder_level_at(branch)
    level.positive? && stock_at(branch) <= level
  end

  class_methods do
    # "Only 3 Claw hammer 16oz left at Moi Avenue", or "... is out of stock at ..." when there's none.
    def shortage_message(product, on_hand, branch)
      on_hand = on_hand.to_d
      if on_hand.positive?
        "Only #{on_hand.to_s("F").delete_suffix(".0")} #{product.name} left at #{branch.name}"
      else
        "#{product.name} is out of stock at #{branch.name}"
      end
    end
  end

  # Movements that must never take expired stock: a customer mustn't be sold it, and another branch mustn't
  # be sent it. Counts, corrections and write-offs may take it, since that's how it leaves.
  IN_DATE_ONLY = %w[ sold transfer_out ].freeze

  # For products tracked by batch, stock in goes to the batch given (a delivery), or back to the
  # batches it came from (a void, a return, a transfer arriving); stock out comes from the batch
  # given (a write-off) or first-expiring-first, skipping expired batches: a sale or transfer that
  # would need them raises Product::ExpiredStock, other movements fall through to them when nothing
  # else is left. Each batch touched gets its own ledger line.
  # With allow_negative: false, stock out that would leave the level below zero raises Product::OutOfStock. The check
  # is made with the level locked, so two tills selling the last one at once can't both have it.
  def move_stock(branch:, quantity:, reason:, source: nil, note: nil, unit_cost_cents: cost_cents, creator: Current.user, batch: nil, reverses: nil, allow_expired: nil, allow_negative: true)
    raise ArgumentError, "#{name} doesn't track stock" unless track_stock?
    allow_expired = !reason.to_s.in?(IN_DATE_ONLY) if allow_expired.nil?

    transaction do
      level = stock_levels.create_or_find_by!(account: account, branch: branch)
      level.lock!
      if !allow_negative && quantity.negative? && level.quantity + quantity.to_d < 0
        raise Product::OutOfStock, Product.shortage_message(self, level.quantity, branch)
      end

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
    # A kit is in stock as many times as its scarcest component allows. A part that doesn't track stock
    # (fitting, say) is always to hand, and selling the kit never deducts it, so it doesn't count.
    def kit_stock_at(branch)
      kit_components.includes(:component).select { _1.component.track_stock? }.map do |part|
        (part.component.stock_at(branch) / part.quantity).floor
      end.min || 0
    end
end
