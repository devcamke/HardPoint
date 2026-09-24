class PurchaseOrdersMailer < ApplicationMailer
  helper CatalogueHelper

  def placed
    @order = params[:purchase_order]
    @account = @order.account
    pdf = PurchaseOrderPdf.new(@order)
    attachments[pdf.filename] = { mime_type: "application/pdf", content: pdf.render }

    mail to: @order.supplier.email, reply_to: @order.creator&.email_address,
      subject: "Purchase order #{@order.reference} from #{@account.name}"
  end
end
