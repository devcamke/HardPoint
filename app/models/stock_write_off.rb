# Stock taken off the books by hand: an adjustment down (damaged, stolen, expired, internal use, a correction), a
# batch written off, or an offcut scrapped. Saying goods were broken is the easy way to cover goods that walked, so past the shop's
# limit (write_off_approval_above, on Shop details) it needs an owner or manager, at their own screen or by
# approval PIN. The limit is on what one person writes off in a day, at cost, so ten small write-offs can't do
# what one big one may not. Each one approved is kept in Activity against the product, and the other owners and
# managers are emailed straight away.
class StockWriteOff
  # Cutting waste counts when it's by hand (an offcut scrapped); what a sale's cuts leave over has the sale as its source.
  REASONS = %w[ damaged stolen expired internal_use correction cutting_waste ].freeze

  attr_reader :product, :branch, :quantity, :reason, :by

  # `quantity` is how much leaves, as a positive number.
  def initialize(product:, branch:, quantity:, reason:, by: Current.user)
    @product, @branch, @quantity, @reason, @by = product, branch, quantity.to_d.abs, reason, by
  end

  def account = product.account

  def value_cents
    (quantity * product.cost_cents).round
  end

  # What this person has already written off by hand today (the shop's day), at cost.
  def earlier_today_cents
    @earlier_today_cents ||= begin
      midnight = Time.use_zone(account.time_zone) { Time.zone.now.beginning_of_day }
      account.stock_movements.where(creator: by, reason: REASONS, source_type: [ nil, "StockAdjustment" ], created_at: midnight..)
        .where("quantity < 0").sum("-quantity * unit_cost_cents").round
    end
  end

  def needs_approval?
    value_cents.positive? && value_cents + earlier_today_cents > account.write_off_approval_above_cents
  end

  def approval_needed_message
    limit = Money.format(account.write_off_approval_above_cents)
    so_far = " (#{Money.format(earlier_today_cents)} already today)" if earlier_today_cents.positive?
    "This writes off #{Money.format(value_cents)} at cost#{so_far}. Writing off more than #{limit} in a day needs a manager's approval PIN"
  end

  # Once the stock has gone: who approved it, kept, and the others told.
  def approved(approver)
    amount = "#{quantity.to_s("F").delete_suffix(".0")} #{product.unit.name.downcase}"
    product.track_event "write_off_approved", creator: by, approver: approver, quantity: amount, reason: reason, branch: branch.name, value: value_cents
    account.alert_owners :large_write_off, product, by: approver, branch: branch, quantity: amount, reason: reason, value_cents: value_cents,
      today_cents: value_cents + earlier_today_cents, written_off_by: by&.name, approver: approver.name
  end
end
