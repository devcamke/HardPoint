# The fundi who brought the customer, and their commission: earned when the sale completes (at each line's rate,
# on its value before tax), taken back in full by a void and in part by a return.
module Sale::Fundis
  extend ActiveSupport::Concern

  included do
    validate { errors.add :fundi, "isn't active" if fundi && fundi_id_changed? && !fundi.active? }
  end

  def change_fundi(fundi)
    raise ArgumentError, "This sale can't be changed" unless open?

    update!(fundi: fundi)
  end

  # Called as the sale completes, inside its transaction.
  def earn_fundi_commission
    return unless fundi

    commission = FundiEntry.commission_for(self)
    return unless commission.positive?

    fundi.entries.create!(account: account, kind: "earned", amount_cents: commission, sales_cents: total_cents - tax_cents, source: self, creator: cashier)
  end

  # A void takes back whatever the sale still holds of the commission.
  def reverse_fundi_commission(by: Current.user)
    held = fundi_commission_held_cents
    fundi.entries.create!(account: account, kind: "reversed", amount_cents: -held, sales_cents: -(total_cents - tax_cents), source: self, creator: by) if fundi && held.positive?
  end

  # A return takes back the commission on the lines brought back, at the rate each was sold under.
  def reverse_fundi_commission_for(sale_return)
    return unless fundi

    share = sale_return.lines.includes(sale_line: { product: { category: :parent } }).sum do |line|
      ((line.total_cents - line.tax_cents) * fundi.commission_percent_for(line.sale_line.product) / 100).round
    end
    share = [ share, fundi_commission_held_cents ].min
    return unless share.positive?

    fundi.entries.create!(account: account, kind: "reversed", amount_cents: -share, sales_cents: -(sale_return.total_cents - sale_return.tax_cents),
      source: sale_return, creator: sale_return.creator)
  end

  # Commission this sale earned less what its void or returns took back.
  def fundi_commission_held_cents
    FundiEntry.where(source: self).or(FundiEntry.where(source: sale_returns)).sum(:amount_cents)
  end
end
