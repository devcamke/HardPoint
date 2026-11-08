# Who owes the shop, by how overdue it is.
class ReceivablesController < ApplicationController
  before_action :ensure_can_manage_receivables

  def show
    rows = Current.account.customers.with_balances
    ageing = Customer.ageing_by_id(rows.map(&:first))
    @rows = rows.map { |customer, balance| [ customer, ageing[customer.id], balance ] }
    @totals = Ageing::BUCKETS.keys.index_with { |bucket| @rows.sum { _2[bucket] } }
  end
end
