# What a scanned or typed code points at: a product, found by any of its barcodes or its SKU, and
# how many of its base unit one scan stands for. A box's barcode is the box: 100 screws, not one.
class ScannedCode
  attr_reader :code, :product, :product_unit

  def initialize(account, code)
    @code = code.to_s.strip
    return if @code.blank?

    barcode = account.barcodes.includes(:product, product_unit: :unit).find_by(code: @code)
    @product = barcode&.product || account.products.find_by(sku: @code.upcase)
    @product_unit = barcode&.product_unit
  end

  def found? = product.present?

  def pack_quantity
    product_unit&.quantity || 1
  end
end
