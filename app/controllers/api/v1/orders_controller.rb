# Quotes and orders; orders made through the API (a web shop's click-and-collect, say) arrive as
# confirmed orders in the shop's "Open orders", to be marked ready and collected at the till as usual.
class Api::V1::OrdersController < Api::V1::BaseController
  def index
    scope = Current.account.customer_orders.includes(:branch, :customer, lines: :product)
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(customer_id: params[:customer_id]) if params[:customer_id].present?
    @orders = paginate(updated_since(scope))
  end

  def show
    @order = Current.account.customer_orders.find(params[:id])
  end

  def create
    idempotently do
      @order = Current.account.customer_orders.new(branch: branch, customer: customer, status: :ordered, ordered_at: Time.current, source: "api",
        needed_by: order_params[:needed_by], note: order_params[:note], lines_attributes: lines_attributes)
      @order.save ? render(:show, status: :created) : render_invalid(@order)
    end
  end

  private
    def order_params
      params.expect(order: [ :branch_id, :customer_id, :needed_by, :note, customer: %i[ name phone email ], lines: [ %i[ product_id sku barcode quantity ] ] ])
    end

    def branch
      order_params[:branch_id].present? ? Current.account.branches.find(order_params[:branch_id]) : Current.account.branches.alphabetically.first
    end

    # An existing customer by id, or found by phone or email, or a new one from the details given.
    def customer
      return Current.account.customers.find(order_params[:customer_id]) if order_params[:customer_id].present?

      details = order_params[:customer] or raise ActionController::BadRequest, "Give customer_id, or customer with a name and phone"
      phone = details[:phone].to_s.gsub(/[^\d+]/, "").presence
      email = details[:email].to_s.strip.downcase.presence
      (phone && Current.account.customers.find_by(phone: phone)) || (email && Current.account.customers.find_by(email: email)) ||
        Current.account.customers.create!(name: details[:name], phone: phone, email: email)
    end

    def lines_attributes
      Array(order_params[:lines]).map do |line|
        product = Current.account.products.find_by(id: line[:product_id]) if line[:product_id].present?
        { account: Current.account, product_code: product&.sku || line[:barcode].presence || line[:sku], quantity: line[:quantity] }
      end
    end
end
