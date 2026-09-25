# What the shop owes its suppliers, by how overdue it is.
class PayablesController < ApplicationController
  before_action :ensure_can_manage_payables

  def show
    @rows = Current.account.suppliers.alphabetically.map { |supplier| [ supplier, supplier.ageing, supplier.balance_cents ] }
      .reject { |_, _, balance| balance.zero? }
    # Suppliers in other currencies are owed in them; the totals convert at today's rates.
    @totals = Ageing::BUCKETS.keys.index_with { |bucket| @rows.sum { |supplier, ageing, _| supplier.to_base_cents(ageing[bucket]) } }
    @total = @rows.sum { |supplier, _, balance| supplier.to_base_cents(balance) }
  end
end
