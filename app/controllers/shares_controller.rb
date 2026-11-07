# Documents sent by WhatsApp (see DocumentShare): opened by customers and suppliers from the link,
# without signing in. Receipts open as the receipt page; everything else as its PDF.
class SharesController < ApplicationController
  allow_unauthenticated_access
  allow_without_two_factor
  allow_while_locked

  def show
    share = DocumentShare.find(params[:token], Current.account)
    return render plain: "This link has expired or isn't valid. Ask #{Current.account.name} to send it again.", status: :not_found unless share

    if share.kind == "receipt"
      @sale = share.record
      render "sales/receipts/show", layout: "receipt"
    else
      pdf = share.pdf
      send_data pdf.render, filename: pdf.filename, type: :pdf, disposition: :inline
    end
  end
end
