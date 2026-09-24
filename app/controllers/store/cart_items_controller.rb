class Store::CartItemsController < Store::BaseController
  rate_limit to: 120, within: 1.minute, with: -> { redirect_to store_cart_path, alert: "Slow down a little and try again." }
  before_action :require_taking_orders
  before_action :set_product, except: :destroy

  def create
    if (problem = cart.add(@product, params[:quantity].presence || 1))
      redirect_back_or_to store_product_path(@product), alert: problem
    else
      save_cart
      redirect_back_or_to store_product_path(@product), notice: "#{@product.name} is in your cart. #{helpers.link_to "View cart", store_cart_path}".html_safe
    end
  end

  def update
    if (problem = cart.set(@product, params[:quantity]))
      redirect_to store_cart_path, alert: problem
    else
      save_cart
      redirect_to store_cart_path, notice: "Cart updated."
    end
  end

  def destroy
    cart.remove(params[:product_id])
    save_cart
    redirect_to store_cart_path, notice: "Removed.", status: :see_other
  end

  private
    def set_product
      @product = storefront.products.find(params[:product_id])
    end
end
