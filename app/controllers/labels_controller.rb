# Shelf and product labels, printed from the browser onto A4 label sheets or a label printer roll.
class LabelsController < ApplicationController
  MAX_PRODUCTS = 200
  FORMATS = { "a4" => "A4 sheet, 3 × 8 labels (70 × 37 mm)", "roll" => "Label printer roll (50 × 25 mm)" }.freeze

  def new
    products = Current.account.products.active
    products = if params[:product_ids].present?
      products.where(id: params[:product_ids])
    else
      scope = products.search(params[:query])
      scope = scope.where(category: Current.account.categories.find(params[:category_id])) if params[:category_id].present?
      scope.alphabetically
    end
    @products = products.limit(MAX_PRODUCTS).includes(:barcodes)
  end

  def show
    copies = params.fetch(:copies, {}).permit!.to_h.transform_values { _1.to_i.clamp(0, 500) }.select { |_, count| count.positive? }
    products = Current.account.products.where(id: copies.keys).includes(:barcodes, :unit).index_by { _1.id.to_s }
    @labels = copies.flat_map { |id, count| [ products[id] ] * count if products[id] }.compact
    @format = FORMATS.key?(params[:format]) ? params[:format] : "a4"

    render layout: "print"
  end
end
