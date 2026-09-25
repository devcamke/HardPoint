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

    # Batch-tracked items: { order line id => [ batch number, expiry date ] }, one batch per item per delivery.
    def draft_batches
      stored = session[:receiving]
      @draft_batches ||= stored.is_a?(Hash) && stored["order_id"] == @order.id ? stored.fetch("batches", {}) : {}
    end

    def save_draft(lines, batches = draft_batches)
      @draft = lines.select { |_, quantity| quantity.positive? }
      @draft_batches = batches.slice(*@draft.keys)
      session[:receiving] = { "order_id" => @order.id, "lines" => @draft.transform_values { _1.to_s("F") }, "batches" => @draft_batches }
    end

    def clear_draft
      session.delete(:receiving)
      @draft = {}
      @draft_batches = {}
    end
end
