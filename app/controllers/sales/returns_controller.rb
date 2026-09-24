# Taking goods back against a receipt, at a till with an open shift (a cash refund comes out of its drawer).
class Sales::ReturnsController < ApplicationController
  include SaleScoped
  before_action :require_till_and_shift, :ensure_returnable

  def new
    @return = Current.account.sale_returns.new(sale: @sale, refund_method: default_refund_method)
  end

  def create
    @return = Current.account.sale_returns.new(return_params.merge(sale: @sale, shift: current_shift, branch: @sale.branch))
    @return.approver = approver_for_action

    if @return.approver.nil?
      flash.now[:alert] = "Returns need a manager's approval PIN."
      render :new, status: :unprocessable_entity
    elsif @return.save
      redirect_to return_path(@return), notice: "Refund #{Money.format(@return.total_cents)} by #{@return.refund_method.humanize.downcase}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def ensure_returnable
      redirect_to @sale, alert: "Nothing on this sale can be returned." unless @sale.returnable?
    end

    def default_refund_method
      @sale.payments.first&.tender.then { |tender| tender.in?(SaleReturn::REFUND_METHODS) ? tender : "cash" }
    end

    def return_params
      permitted = params.expect(sale_return: [ :refund_method, :reason, lines_attributes: [ [ :sale_line_id, :quantity, :restock ] ] ])
      permitted[:lines_attributes]&.each_value { |line| line[:account] = Current.account }
      permitted
    end
end
