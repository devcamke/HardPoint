# Documents sent by WhatsApp (see DocumentShare). Staff press the WhatsApp button, which makes a link and opens
# WhatsApp with the message written (create). Customers and suppliers open the link without signing in (show):
# receipts as the receipt page, everything else as its PDF. A link can be taken back (destroy).
class SharesController < ApplicationController
  include SharedDocument
  allow_unauthenticated_access only: :show
  allow_without_two_factor only: :show
  allow_while_locked
  before_action :set_document, only: :create

  def create
    share = DocumentShare.create_for!(@document, from: period(:from), to: period(:to))
    redirect_to whatsapp_url(params[:phone], share.message), allow_other_host: true
  end

  def show
    share = DocumentShare.open(params[:token], Current.account)
    return render plain: "This link has expired or isn't valid. Ask #{Current.account.name} to send it again.", status: :not_found unless share

    if share.kind == "receipt" && params[:format] != "pdf"
      @sale = share.record
      render "sales/receipts/show", layout: "receipt"
    else
      pdf = share.pdf
      send_data pdf.render, filename: pdf.filename, type: :pdf, disposition: :inline
    end
  end

  def destroy
    share = Current.account.document_shares.find(params[:id])
    return head(:not_found) unless allowed_document?(share.document)

    share.revoke
    redirect_back_or_to root_path, notice: "That link no longer opens anything.", status: :see_other
  end

  private
    def whatsapp_url(phone, text)
      "https://wa.me/#{PhoneNumber.normalize(phone)}?#{{ text: text }.to_query}"
    end
end
