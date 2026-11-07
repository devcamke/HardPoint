# What the shop owes its suppliers, by how overdue it is.
class PayablesController < ApplicationController
  before_action :ensure_can_manage_payables

  def show
    balances = Supplier.balances_by_id.reject { _2.zero? }
    suppliers = Current.account.suppliers.where(id: balances.keys).alphabetically.to_a
    ageing = Supplier.ageing_by_id(suppliers)
    @rows = suppliers.map { |supplier| [ supplier, ageing[supplier.id], balances[supplier.id] ] }
    # Suppliers in other currencies are owed in them; the totals convert at today's rates.
    @totals = Ageing::BUCKETS.keys.index_with { |bucket| @rows.sum { |supplier, ageing, _| supplier.to_base_cents(ageing[bucket]) } }
    @total = @rows.sum { |supplier, _, balance| supplier.to_base_cents(balance) }
  end
end
