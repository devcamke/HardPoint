# Recording the checked-in delivery: a goods received note that puts it into stock.
class Mobile::GoodsReceiptsController < Mobile::BaseController
  include MobileReceiving

  def create
    return redirect_to mobile_purchase_order_path(@order), alert: "Scan or check in what arrived first." if draft.empty?

    receipt = Current.account.goods_receipts.new(purchase_order: @order, supplier: @order.supplier, branch: @order.branch,
      supplier_reference: params[:supplier_reference], note: params[:note])
    @order.lines.each do |line|
      quantity = draft[line.id.to_s]
      receipt.lines.build(account: Current.account, purchase_order_line: line, product: line.product, quantity: quantity) if quantity
    end

    if receipt.save
      clear_draft
      redirect_to mobile_purchase_orders_path, notice: "#{receipt.reference} recorded: #{helpers.pluralize(receipt.lines.size, "item")} into stock at #{receipt.branch.name}."
    else
      redirect_to mobile_purchase_order_path(@order), alert: receipt.errors.full_messages.to_sentence
    end
  end
end
