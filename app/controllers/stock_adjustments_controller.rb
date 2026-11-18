class StockAdjustmentsController < ApplicationController
  before_action :ensure_can_manage_stock

  def new
    @adjustment = Current.account.stock_adjustments.new(product: Current.account.products.find(params[:product_id]), branch: selected_branch)
  end

  def create
    @adjustment = Current.account.stock_adjustments.new(adjustment_params)
    write_off = write_off_for(@adjustment)
    approver = approver_for_action if write_off&.needs_approval?

    if write_off&.needs_approval? && approver.nil?
      @adjustment.errors.add :base, write_off.approval_needed_message
      render :new, status: :unprocessable_entity
    elsif @adjustment.save
      write_off.approved(approver) if approver
      redirect_to @adjustment.product, notice: "Stock at #{@adjustment.branch.name} is now #{helpers.quantity(@adjustment.product.stock_at(@adjustment.branch), @adjustment.product.unit)}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    # Stock going out by hand, if that's what this is (StockWriteOff).
    def write_off_for(adjustment)
      return unless adjustment.valid? && adjustment.quantity.negative?

      StockWriteOff.new(product: adjustment.product, branch: adjustment.branch, quantity: adjustment.quantity, reason: adjustment.reason)
    end

    def adjustment_params
      permitted = params.expect(stock_adjustment: %i[ product_id branch_id reason quantity note ])
      permitted.merge(product: Current.account.products.find(permitted.delete(:product_id)),
        branch: visible_branches.find(permitted.delete(:branch_id)))
    end
end
