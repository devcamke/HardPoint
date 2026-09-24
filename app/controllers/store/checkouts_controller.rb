class Store::CheckoutsController < Store::BaseController
  rate_limit to: 10, within: 10.minutes, only: :create, with: -> { redirect_to new_store_checkout_path, alert: "Too many orders from here just now. Please call us." }
  before_action :require_taking_orders
  before_action { redirect_to store_cart_path if cart.empty? }

  def new
    @checkout = Storefront::Checkout.new(storefront: storefront, cart: cart)
  end

  def create
    @checkout = Storefront::Checkout.new(storefront: storefront, cart: cart, **checkout_params)
    if @checkout.place
      save_cart
      redirect_to store_order_path(@checkout.order.tracking_token), status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def checkout_params
      params.expect(checkout: %i[ name phone email branch_id note website ]).to_h.symbolize_keys
    end
end
