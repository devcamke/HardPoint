# Shared by the till's controllers: the sale being rung up now, and re-rendering the cart.
module PosSale
  extend ActiveSupport::Concern

  included do
    before_action :ensure_can_sell, :require_till_and_shift, :set_sale
  end

  ApprovalMissing = Class.new(StandardError)
  PaidAlready = Class.new(StandardError)

  private
    def set_sale
      @sale = current_shift.current_sale
    end

    # Discounts past the shop's limit need an owner or manager: at the till, or by approval PIN.
    # Raised inside the transaction that applied the discount, so it's rolled back. The percentage can also grow
    # without a discount being touched: a line removed, a quantity cut, a customer with lower prices chosen. Every
    # change that recalculates the sale runs this, so an approved 5% can't quietly become 50%.
    def approve_discount!
      return unless @sale.discount_needs_approval?

      approver = approver_for_action
      unless approver
        limit = Current.account.max_cashier_discount_percent.to_s("F").delete_suffix(".0")
        raise ApprovalMissing, "That makes the discount #{@sale.highest_discount_percent.round(1).to_s.delete_suffix(".0")}% of the sale. " \
          "A discount over #{limit}% needs a manager's approval PIN"
      end

      @sale.update!(discount_approver: approver, approved_discount_percent: @sale.highest_discount_percent.ceil(2))
      @sale.track_event "discount_approved", approver: approver, percent: @sale.highest_discount_percent.round(1)
    end

    # Once money has been taken, the sale can't shrink to it or below it: the payment would be left paying for
    # nothing, a sale paid in full can only complete through a further payment, and with the last line gone the
    # sale would be swept away at shift close with the money still on it.
    def keep_what_is_paid!
      return if @sale.payments.none? || @sale.balance_due_cents.positive?

      raise PaidAlready, "#{Money.format(@sale.paid_cents)} has already been taken on this sale. Remove the payment first"
    end

    def render_cart(message: nil, alert: nil, status: :ok)
      respond_to do |format|
        format.turbo_stream do
          sale = @sale.reload_for_cart
          render turbo_stream: [
            turbo_stream.replace("cart", partial: "pos/cart", locals: { sale: sale }),
            turbo_stream.replace("pane_tabs", partial: "pos/pane_tabs", locals: { sale: sale }),
            turbo_stream.update("pos_message", partial: "pos/message", locals: { message: message, alert: alert }),
            turbo_stream.remove("completed_sale")
          ], status: status
        end
        format.html { redirect_to pos_path, notice: message, alert: alert }
      end
    end
end
