# What the shop owes its suppliers, by how overdue it is.
class PayablesController < ApplicationController
  before_action :ensure_can_manage_payables

  def show
    @rows = Current.account.suppliers.alphabetically.map { |supplier| [ supplier, supplier.ageing, supplier.balance_cents ] }
      .reject { |_, _, balance| balance.zero? }
    @totals = Ageing::BUCKETS.keys.index_with { |bucket| @rows.sum { _2[bucket] } }
  end
end
