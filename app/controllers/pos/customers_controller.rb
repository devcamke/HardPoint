# Finding a customer at the till (index) and putting the current sale in their name (update).
class Pos::CustomersController < ApplicationController
  include PosSale
  skip_before_action :require_till_and_shift, :set_sale, only: :index

  def index
    @customers = Current.account.customers.search(params[:query]).alphabetically.includes(:price_list).limit(10)
  end

  def update
    customer = params[:customer_id].presence && Current.account.customers.find(params[:customer_id])
    Sale.transaction do
      @sale.change_customer(customer)
      approve_discount!
    end
    render_cart message: customer ? "#{customer.name}#{" · #{customer.price_list.name} prices" if customer.price_list}" : "Walk-in customer"
  rescue ApprovalMissing, ArgumentError => error
    render_cart alert: error.message, status: :unprocessable_entity
  end
end
