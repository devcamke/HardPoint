# Receiving a delivery on the phone against a purchase order. What's been checked in so far is
# kept in the session (one order at a time, { order line id => quantity }) until the delivery is
# recorded as a goods received note.
module MobileReceiving
  extend ActiveSupport::Concern

  included do
    before_action :ensure_can_purchase, :set_purchase_order
  end

  private
    def set_purchase_order
      @order = Current.account.purchase_orders.includes(lines: { product: :unit }).find(params[:purchase_order_id] || params[:id])
    end

    def draft
      stored = session[:receiving]
      @draft ||= stored.is_a?(Hash) && stored["order_id"] == @order.id ? stored["lines"].transform_values(&:to_d) : {}
    end

    def save_draft(lines)
      @draft = lines.select { |_, quantity| quantity.positive? }
      session[:receiving] = { "order_id" => @order.id, "lines" => @draft.transform_values { _1.to_s("F") } }
    end

    def clear_draft
      session.delete(:receiving)
      @draft = {}
    end
end
