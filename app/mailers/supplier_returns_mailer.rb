class SupplierReturnsMailer < ApplicationMailer
  helper CatalogueHelper

  def debit_note
    @return = params[:supplier_return]
    @account = @return.account
    pdf = SupplierReturnPdf.new(@return)
    attachments[pdf.filename] = { mime_type: "application/pdf", content: pdf.render }

    mail to: @return.supplier.email, reply_to: @return.creator&.email_address,
      subject: "Debit note #{@return.reference} from #{@account.name}: goods returned"
  end
end
