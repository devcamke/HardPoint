# A customer's cart in the online store, kept in their session as { product id => quantity }.
# Only products the store sells count; anything taken off sale since drops out.
class Storefront::Cart
  # Priced the way the order will be charged (Storefront::Checkout carries these prices onto it): the retail
  # price with any quantity break, less the best offer running at every branch. No customer's price list
  # applies online, since anyone can type anyone's phone number, and a branch's own offer isn't shown because
  # the customer hasn't chosen a branch yet.
  Line = Data.define(:product, :quantity) do
    def list_price_cents = product.price_cents_for(quantity: quantity)
    def offer = product.promotion_price(unit_price_cents: list_price_cents)
    def promotion = offer&.first
    def unit_price_cents = offer&.last || list_price_cents
    def total_cents = (unit_price_cents * quantity).round
  end

  MAX_LINES = 40
  MAX_QUANTITY = 10_000

  def initialize(storefront, items)
    @storefront = storefront
    @items = items
  end

  # Returns an error message, or nil when the cart changed.
  def add(product, quantity)
    set(product, (@items[product.id.to_s].to_d + quantity.to_d))
  end

  def set(product, quantity)
    quantity = quantity.to_d
    return "Choose a quantity" unless quantity.positive?
    return "That's more than we can take online; call us for large orders" if quantity > MAX_QUANTITY
    return "#{product.name} is sold in whole #{product.unit.name.downcase.pluralize}" unless product.quantity_allowed?(quantity)
    return "Your cart is full; place this order and start another" if !@items.key?(product.id.to_s) && @items.size >= MAX_LINES
    if product.track_stock? && !product.kit? && @storefront.collection_branches.none? { product.available_at(_1) >= quantity }
      return "Only #{@storefront.collection_branches.map { product.available_at(_1) }.max.to_s("F").delete_suffix(".0")} #{product.name} left to order right now"
    end

    @items[product.id.to_s] = quantity.to_s("F")
    @lines = nil
  end

  def remove(product_id)
    @items.delete(product_id.to_s)
    @lines = nil
  end

  def clear
    @items.clear
    @lines = nil
  end

  def lines
    @lines ||= begin
      products = @storefront.products.where(id: @items.keys).includes(:unit, :stock_levels, image_attachment: :blob).index_by(&:id)
      @items.filter_map { |id, quantity| Line.new(products[id.to_i], quantity.to_d) if products[id.to_i] }
    end
  end

  def quantity_of(product)
    @items[product.id.to_s]&.to_d
  end

  def empty? = lines.empty?
  def count = lines.size
  def total_cents = lines.sum(&:total_cents)
end
