# Counting by scanner: scan a barcode (or type a SKU) and the quantity found.
class StockCounts::ScansController < ApplicationController
  include StockCountScoped
  before_action :ensure_can_manage_stock, :ensure_counting

  def create
    product = Current.account.products.find_by_code(params[:code])
    line = product && @count.lines.find_by(product: product)

    if line.nil?
      redirect_to @count, alert: "“#{params[:code]}” isn't in this stock take.", status: :see_other
    elsif line.update(counted_quantity: params[:counted_quantity])
      redirect_to @count, notice: "#{product.name}: #{helpers.quantity(line.counted_quantity, product.unit)} counted.", status: :see_other
    else
      redirect_to @count, alert: line.errors.full_messages.to_sentence, status: :see_other
    end
  end
end
