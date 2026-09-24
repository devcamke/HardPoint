# Stock is an append-only ledger of movements; stock_levels caches each branch's balance and is
# updated in the same transaction, under a row lock, so balances are always explainable.
module Product::Stockable
  extend ActiveSupport::Concern

  included do
    has_many :stock_levels, dependent: :destroy
    has_many :stock_movements, dependent: :restrict_with_error

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

  def below_reorder_level_at?(branch)
    reorder_level.positive? && stock_at(branch) <= reorder_level
  end

  def move_stock(branch:, quantity:, reason:, source: nil, note: nil, unit_cost_cents: cost_cents, creator: Current.user)
    raise ArgumentError, "#{name} doesn't track stock" unless track_stock?

    transaction do
      level = stock_levels.create_or_find_by!(account: account, branch: branch)
      level.lock!
      level.update! quantity: level.quantity + quantity.to_d

      stock_movements.create! account: account, branch: branch, quantity: quantity, balance: level.quantity,
        reason: reason, source: source, note: note, unit_cost_cents: unit_cost_cents, creator: creator
    end
  end

  private
    # A kit is in stock as many times as its scarcest component allows.
    def kit_stock_at(branch)
      kit_components.includes(:component).map do |part|
        (part.component.stock_at(branch) / part.quantity).floor
      end.min || 0
    end
end
