# Goods going back to suppliers, each with its debit note.
class SupplierReturnsController < ApplicationController
  BLANK_LINES = 5

  before_action :ensure_can_purchase_or_pay, only: %i[ index show ]
  before_action :ensure_can_purchase, only: %i[ new create ]

  def index
    @filter = params[:filter] == "all" ? "all" : "awaiting"
    returns = Current.account.supplier_returns.chronologically.includes(:supplier, :branch)
    returns = returns.awaiting_credit if @filter == "awaiting"
    @supplier_returns = paginate(returns)
  end

  def show
    @supplier_return = Current.account.supplier_returns.find(params[:id])
    respond_to do |format|
      format.html
      format.pdf do
        pdf = SupplierReturnPdf.new(@supplier_return)
        send_data pdf.render, filename: pdf.filename, type: :pdf, disposition: :inline
      end
    end
  end

  # From a delivery: its products, ready for how many go back. Otherwise blank lines to scan into.
  def new
    receipt = Current.account.goods_receipts.find_by(id: params[:goods_receipt_id])
    supplier = receipt&.supplier || Current.account.suppliers.find_by(id: params[:supplier_id])
    @supplier_return = Current.account.supplier_returns.new(goods_receipt: receipt, supplier: supplier, branch: receipt&.branch || selected_branch, reason: "damaged")
    if receipt
      receipt.lines.includes(:product).each { |line| @supplier_return.lines.build(product: line.product) }
    else
      BLANK_LINES.times { @supplier_return.lines.build }
    end
  end

  def create
    @supplier_return = Current.account.supplier_returns.new(supplier_return_params)

    if @supplier_return.save
      email = params[:email] == "1" && @supplier_return.supplier.email.present?
      SupplierReturnsMailer.with(supplier_return: @supplier_return).debit_note.deliver_later if email
      redirect_to @supplier_return, notice: "#{@supplier_return.reference} recorded: the goods are out of stock and #{helpers.money(@supplier_return.total_cents, currency: @supplier_return.currency)} is off what we owe #{@supplier_return.supplier.name}.#{" Debit note emailed to #{@supplier_return.supplier.email}." if email}"
    else
      @supplier_return.lines.build while @supplier_return.lines.size < BLANK_LINES && @supplier_return.goods_receipt.nil?
      render :new, status: :unprocessable_entity
    end
  end

  private
    def supplier_return_params
      permitted = params.expect(supplier_return: [ :supplier_id, :branch_id, :goods_receipt_id, :reason, :note,
        lines_attributes: [ [ :product_id, :product_code, :quantity, :unit_cost, :stock_batch_id ] ] ])
      receipt = Current.account.goods_receipts.find(permitted.delete(:goods_receipt_id)) if permitted[:goods_receipt_id].present?
      permitted[:goods_receipt] = receipt
      permitted[:supplier] = receipt&.supplier || Current.account.suppliers.find(permitted[:supplier_id])
      permitted[:branch] = receipt&.branch || Current.account.branches.find(permitted[:branch_id])
      permitted.delete(:supplier_id)
      permitted.delete(:branch_id)
      permitted[:lines_attributes]&.each_value do |line|
        line[:account] = Current.account
        line[:product] = Current.account.products.find(line.delete(:product_id)) if line[:product_id].present?
        line[:stock_batch] = Current.account.stock_batches.find(line.delete(:stock_batch_id)) if line[:stock_batch_id].present?
        line.delete(:product_id)
        line.delete(:stock_batch_id)
        line.delete(:unit_cost) if line[:unit_cost].blank?
      end
      permitted
    end
end
