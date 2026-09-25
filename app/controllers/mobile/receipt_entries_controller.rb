# How many of an item came: added to what's been checked in so far, or set. "Everything" checks in
# all that's still to come, for a delivery that's plainly complete.
class Mobile::ReceiptEntriesController < Mobile::BaseController
  include MobileReceiving

  def create
    lines = draft.dup

    if params[:everything]
      @order.outstanding_lines.each { lines[_1.id.to_s] = _1.outstanding_quantity }
      save_draft(lines)
      return redirect_to mobile_purchase_order_path(@order), notice: "Everything still to come is checked in. Adjust anything short, then record the delivery."
    end

    @line = @order.lines.find { _1.id == params[:line_id].to_i } or raise ActiveRecord::RecordNotFound
    amount = entered_quantity(@line.product)
    total = params[:mode] == "set" ? amount : lines.fetch(@line.id.to_s, 0) + amount

    if amount.negative? || !@line.product.quantity_allowed?(total)
      @error = "Enter a whole number of #{@line.product.unit.name.pluralize.downcase}"
    elsif total > @line.outstanding_quantity
      @error = "Only #{helpers.quantity(@line.outstanding_quantity, @line.product.unit)} of #{@line.product.name} still to come on this order. Extra goes on a separate receipt in HardPoint."
    else
      lines[@line.id.to_s] = total
      save_draft(lines)
    end
    render status: @error ? :unprocessable_entity : :ok
  end
end
