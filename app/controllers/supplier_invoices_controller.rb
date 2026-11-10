class SupplierInvoicesController < ApplicationController
  before_action :ensure_can_manage_payables

  def index
    invoices = Current.account.supplier_invoices.chronologically.includes(:supplier)
    invoices = invoices.where(supplier_id: Current.account.suppliers.search(params[:query]).select(:id)) if params[:query].present?
    @invoices = paginate(invoices)
  end

  def show
    @invoice = Current.account.supplier_invoices.find(params[:id])
  end

  def new
    receipt = Current.account.goods_receipts.find_by(id: params[:goods_receipt_id])
    # The invoice is for the goods, in the supplier's currency; the transport and duty on the delivery were paid here.
    @invoice = Current.account.supplier_invoices.new(invoice_date: Date.current, goods_receipt: receipt,
      supplier: receipt&.supplier || Current.account.suppliers.find_by(id: params[:supplier_id]), total_cents: receipt&.goods_value_cents)
  end

  def create
    @invoice = Current.account.supplier_invoices.new(invoice_params)

    if @invoice.save
      flash[:alert] = "Check it: the invoice is #{@invoice.variance_description}." if @invoice.variance?
      redirect_to @invoice.supplier, notice: "Invoice #{@invoice.number} recorded, due #{@invoice.due_date.to_fs(:long)}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def invoice_params
      permitted = params.expect(supplier_invoice: %i[ supplier_id goods_receipt_id number invoice_date due_date total tax note ])
      permitted[:supplier] = Current.account.suppliers.find(permitted.delete(:supplier_id))
      permitted[:goods_receipt] = Current.account.goods_receipts.find(permitted.delete(:goods_receipt_id)) if permitted[:goods_receipt_id].present?
      permitted.delete(:goods_receipt_id)
      permitted
    end
end
