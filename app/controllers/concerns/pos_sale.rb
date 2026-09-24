# Shared by the till's controllers: the sale being rung up now, and re-rendering the cart.
module PosSale
  extend ActiveSupport::Concern

  included do
    before_action :ensure_can_sell, :require_till_and_shift, :set_sale
  end

  ApprovalMissing = Class.new(StandardError)

  private
    def set_sale
      @sale = current_shift.current_sale
    end

    # Discounts past the shop's limit need an owner or manager: at the till, or by approval PIN.
    # Raised inside the transaction that applied the discount, so it's rolled back.
    def approve_discount!
      return unless @sale.discount_needs_approval?

      approver = approver_for_action
      raise ApprovalMissing, "A discount over #{Current.account.max_cashier_discount_percent.to_s("F").delete_suffix(".0")}% needs a manager's approval PIN" unless approver

      @sale.update!(discount_approver: approver, approved_discount_percent: @sale.highest_discount_percent.ceil(2))
      @sale.track_event "discount_approved", approver: approver.name, percent: @sale.highest_discount_percent.round(1)
    end

    def render_cart(message: nil, alert: nil, status: :ok)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("cart", partial: "pos/cart", locals: { sale: @sale.reload }),
            turbo_stream.replace("pos_message", partial: "pos/message", locals: { message: message, alert: alert }),
            turbo_stream.remove("completed_sale")
          ], status: status
        end
        format.html { redirect_to pos_path, notice: message, alert: alert }
      end
    end
end
