# An invoice from KRA recorded on its own: the goods are in already, or it was for a service.
class EtimsPurchases::InvoicesController < EtimsPurchases::BaseController
  before_action :ensure_can_manage_payables

  def create
    receipt = within_visible_branches(Current.account.goods_receipts).find(params[:goods_receipt_id]) if params[:goods_receipt_id].present?

    if @purchase.record_invoice(goods_receipt: receipt)
      flash[:alert] = "Check it: the invoice is #{@purchase.supplier_invoice.variance_description}." if @purchase.supplier_invoice.variance?
      redirect_to @purchase.supplier, notice: "Invoice #{@purchase.invoice_number} recorded, due #{@purchase.supplier_invoice.due_date.to_fs(:long)}."
    else
      back_with_errors
    end
  end
end
