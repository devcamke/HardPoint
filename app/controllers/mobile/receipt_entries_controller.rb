# How many of an item came: added to what's been checked in so far, or set. "Everything" checks in
# all that's still to come, for a delivery that's plainly complete.
class Mobile::ReceiptEntriesController < Mobile::BaseController
  include MobileReceiving

  def create
    lines = draft.dup

    if params[:everything]
      @order.outstanding_lines.reject { _1.product.tracks_batches? }.each { lines[_1.id.to_s] = _1.outstanding_quantity }
      save_draft(lines)
      return redirect_to mobile_purchase_order_path(@order), notice: "Everything still to come is checked in. Adjust anything short, then record the delivery."
    end

    @line = @order.lines.find { _1.id == params[:line_id].to_i } or raise ActiveRecord::RecordNotFound
    amount = entered_quantity(@line.product)
    total = params[:mode] == "set" ? amount : lines.fetch(@line.id.to_s, 0) + amount

    if amount.negative? || !@line.product.quantity_allowed?(total)
      @error = "Enter a whole number of #{@line.product.unit.name.pluralize.downcase}"
    elsif (batch_error = batch_problem)
      @error = batch_error
    elsif total > @line.outstanding_quantity
      @error = "Only #{helpers.quantity(@line.outstanding_quantity, @line.product.unit)} of #{@line.product.name} still to come on this order. Extra goes on a separate receipt in HardPoint."
    else
      lines[@line.id.to_s] = total
      batches = draft_batches.dup
      batches[@line.id.to_s] = [ params[:batch_number].to_s.squish.upcase, params[:expires_on].presence ] if @line.product.tracks_batches?
      save_draft(lines, batches)
    end
    render status: @error ? :unprocessable_entity : :ok
  end

  private
    def batch_problem
      return unless @line.product.tracks_batches?

      number = params[:batch_number].to_s.squish.upcase
      recorded = draft_batches[@line.id.to_s]&.first
      if number.blank?
        "Enter the batch number printed on #{@line.product.name}"
      elsif recorded && recorded != number && params[:mode] != "set"
        "Batch #{recorded} is already checked in for #{@line.product.name}. Record this delivery first, then receive batch #{number} as another delivery."
      end
    end
end
