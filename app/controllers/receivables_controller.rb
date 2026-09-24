# Who owes the shop, by how overdue it is.
class ReceivablesController < ApplicationController
  before_action :ensure_can_manage_receivables

  def show
    @rows = Current.account.customers.with_balances.map { |customer, balance| [ customer, customer.ageing, balance ] }
    @totals = Ageing::BUCKETS.keys.index_with { |bucket| @rows.sum { _2[bucket] } }
  end
end
