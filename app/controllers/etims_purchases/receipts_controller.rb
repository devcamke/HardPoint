# The goods on an invoice from KRA go into stock, and the invoice onto what the shop owes.
class EtimsPurchases::ReceiptsController < EtimsPurchases::BaseController
  before_action :ensure_can_purchase

  def create
    # One set of fields per line of the invoice, by line number; anything else sent is ignored.
    choices = @purchase.lines.to_h do |line|
      fields = params.dig(:lines, line.seq.to_s)
      [ line.seq.to_s, fields.respond_to?(:permit) ? fields.permit(:product_code, :quantity, :unit_cost, :batch_number, :expires_on, :skip).to_h : {} ]
    end

    if @purchase.receive(choices)
      redirect_to @purchase.goods_receipt, notice: "Received into #{@purchase.branch.name}, and invoice #{@purchase.invoice_number} recorded: " \
        "#{helpers.money(@purchase.total_cents)} due #{@purchase.supplier_invoice.due_date.to_fs(:long)}."
    else
      back_with_errors
    end
  end
end
