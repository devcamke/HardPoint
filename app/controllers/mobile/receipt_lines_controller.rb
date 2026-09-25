# The item just scanned from a delivery, found on the order, ready for how many came.
class Mobile::ReceiptLinesController < Mobile::BaseController
  include MobileReceiving

  def index
    @line = scanned.found? ? @order.lines.find { _1.product_id == scanned.product.id } : nil
    return render :not_found, status: :not_found unless @line
    draft
  end
end
