# Everything in the owner's morning email for one day: the takings (from the dashboard, so the figures agree), then
# what's worth a look, on stock and on money and staff. Each list is empty when there's nothing to say, and the
# email leaves it out.
class OwnerSummary::Daily
  # Stock leaving for something other than a sale or a transfer: the shop's loss, valued at cost.
  WRITE_OFF_REASONS = %w[ damaged stolen expired internal_use lost_in_transit correction count cutting_waste ].freeze
  LIST_LIMIT = 8

  Shift = Data.define(:name, :cashier, :variance_cents)
  Cashier = Data.define(:name, :sales, :discount_cents, :voids, :voided_cents, :returns, :returned_cents) do
    def given_away_cents = discount_cents + voided_cents + returned_cents
  end
  BelowCost = Data.define(:sale, :product_name, :sold_cents, :cost_cents) do
    def loss_cents = cost_cents - sold_cents
  end
  Flag = Data.define(:receipt_number, :warnings)
  OutOfStock = Data.define(:branch, :count, :products)
  Refusal = Data.define(:product, :times, :quantity)
  WriteOff = Data.define(:reason, :value_cents, :lines)

  attr_reader :account, :date

  def initialize(account, date)
    @account = account
    @date = date
  end

  def dashboard = @dashboard ||= Dashboard.new(account, date: date)
  def totals = @totals ||= dashboard.totals
  def currency = account.currency
  delegate :change_on_last_week_percent, :average_sale_cents, :takings_by_hour, :last_seven_days, :takings_by_branch, :top_products, to: :dashboard

  # Label → amount, in the report's own order (which methods it shows depends on the shop). Refunds are kept apart.
  def payments
    @payments ||= begin
      section = Report::Payments.new(account: account, period: period).sections.first
      section.columns.map(&:label).zip(section.totals).to_h
        .slice(*Report::Payments::TENDER_LABELS.values).select { |_, cents| cents.to_i.positive? }
    end
  end

  def refunds_cents
    @refunds_cents ||= begin
      section = Report::Payments.new(account: account, period: period).sections.first
      section.columns.map(&:label).zip(section.totals).to_h["Refunds"].to_i.abs
    end
  end

  # Every shift that closed on the day, with how its cash count came out.
  def shifts
    @shifts ||= account.shifts.closed.where(closed_at: period.range).includes(:register, :opened_by).order(:closed_at)
      .map { Shift.new(_1.name, _1.opened_by.name, _1.variance_cents.to_i) }
  end

  # Discounts, voids and returns per cashier, for those who gave any away.
  def cashiers
    @cashiers ||= Report::DiscountsAndVoids.new(account: account, period: period).sections.first.rows
      .map { |name, sales, discount, _discounted, voids, voided, returns, returned| Cashier.new(name, sales, discount, voids, voided, returns, returned) }
      .select { _1.given_away_cents.positive? }.sort_by { -_1.given_away_cents }
  end

  # Cashiers whose day stood out against their own usual (CashierPatterns).
  def unusual
    @unusual ||= CashierPatterns.new(account, date).flags
  end

  # Lines sold for less than they cost, ex tax: a price set too low, or a discount too deep.
  def below_cost
    @below_cost ||= SaleLine.joins(:sale).includes(:product, :sale)
      .where(sales: { account_id: account.id, status: "completed", completed_at: period.range })
      .where("sale_lines.cost_cents > 0 AND sale_lines.total_cents - sale_lines.tax_cents < sale_lines.cost_cents")
      .order(Arel.sql("sale_lines.cost_cents - (sale_lines.total_cents - sale_lines.tax_cents) DESC"))
      .map { BelowCost.new(_1.sale, _1.product.name, _1.total_cents - _1.tax_cents, _1.cost_cents) }
  end

  # Sales an offline till sent in with something a manager should check.
  def offline_flags
    @offline_flags ||= account.account_events.where(action: "recorded_offline", eventable_type: "Sale", created_at: period.range)
      .where("jsonb_array_length(COALESCE(particulars->'warnings', '[]'::jsonb)) > 0").order(:created_at)
      .map { Flag.new(Sale.find_by(id: _1.eventable_id)&.receipt_number || _1.particulars["offline_receipt_number"], _1.particulars["warnings"]) }
  end

  # Tills still open from before today: their cash hasn't been counted.
  def shifts_left_open
    @shifts_left_open ||= account.shifts.open.where(opened_at: ...Time.zone.today.beginning_of_day).includes(:register, :opened_by).order(:opened_at).to_a
  end

  # M-Pesa paid in on the day that isn't on any sale or account yet.
  def unmatched_mobile_money
    @unmatched_mobile_money ||= begin
      scope = account.mpesa_transactions.unmatched.where(transacted_at: period.range)
      { count: scope.count, cents: scope.sum(:amount_cents) }
    end
  end

  # Per branch, products at nothing (or less) where the shop carries them, the best sellers first: each one a sale lost.
  def out_of_stock
    @out_of_stock ||= account.branches.alphabetically.filter_map do |branch|
      levels = account.stock_levels.joins(:product).merge(account.products.active.where(track_stock: true, kit: false))
        .where(branch: branch).where("stock_levels.quantity <= 0")
      next if levels.none?

      sold = SaleLine.joins(:sale).where(sales: { branch_id: branch.id, status: "completed", completed_at: 30.days.ago.. })
        .group(:product_id).sum(:quantity)
      products = levels.includes(product: :unit).map(&:product).sort_by { [ -sold.fetch(_1.id, 0), _1.name ] }
      OutOfStock.new(branch, products.size, products.first(LIST_LIMIT))
    end
  end

  # What the till turned away for want of stock, the most asked-for first.
  def refusals
    @refusals ||= begin
      counts = account.stock_refusals.where(created_at: period.range).by_product
      products = account.products.where(id: counts.map(&:first)).includes(:unit).index_by(&:id)
      counts.filter_map { |id, times, quantity| Refusal.new(products[id], times, quantity) if products[id] }
    end
  end

  # Stock one branch could send another that's short, before anyone orders more.
  def moves
    @moves ||= account.branches.many? ? BranchRebalancing.new(account).moves : []
  end

  def below_zero_count
    @below_zero_count ||= account.stock_levels.where("quantity < 0").count
  end

  # Stock written off on the day, by reason, valued at cost.
  def write_offs
    @write_offs ||= account.stock_movements.where(created_at: period.range, reason: WRITE_OFF_REASONS).where("quantity < 0")
      .includes(:product, :creator).group_by(&:reason)
      .map { |reason, lines| WriteOff.new(reason, lines.sum { (-_1.quantity * _1.unit_cost_cents).round }, lines) }
      .sort_by { -_1.value_cents }
  end

  def stock_worth_a_look? = out_of_stock.any? || refusals.any? || below_zero_count.positive? || write_offs.any? || moves.any?

  def money_worth_a_look?
    shifts.any? { _1.variance_cents.nonzero? } || cashiers.any? || unusual.any? || below_cost.any? || offline_flags.any? || shifts_left_open.any? ||
      unmatched_mobile_money[:count].positive?
  end

  private
    def period = Report::Period.new(from: date, to: date)
end
