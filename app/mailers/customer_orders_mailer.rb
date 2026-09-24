class CustomerOrdersMailer < ApplicationMailer
  helper CatalogueHelper

  def document
    @order = params[:customer_order]
    @account = @order.account
    pdf = CustomerOrderPdf.new(@order)
    attachments[pdf.filename] = { mime_type: "application/pdf", content: pdf.render }

    mail to: params[:email], reply_to: params[:sender]&.email_address,
      subject: "#{@order.kind} #{@order.reference} from #{@account.name}"
  end
end
