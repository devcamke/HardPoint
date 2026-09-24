# The products a supplier sells: their code for it, their price, lead time and minimum order.
class Suppliers::ProductsController < ApplicationController
  before_action :ensure_can_purchase, :set_supplier

  def create
    supplier_product = @supplier.supplier_products.new(supplier_product_params.merge(account: Current.account,
      product: Current.account.products.find_by_code(params.dig(:supplier_product, :product_code))))

    if supplier_product.product.nil?
      redirect_to @supplier, alert: "No product with barcode or SKU “#{params.dig(:supplier_product, :product_code)}”.", status: :see_other
    elsif supplier_product.save
      redirect_to @supplier, notice: "#{supplier_product.product.name} added.", status: :see_other
    else
      redirect_to @supplier, alert: supplier_product.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def update
    supplier_product = @supplier.supplier_products.find(params[:id])

    if supplier_product.update(supplier_product_params)
      redirect_to @supplier, notice: "#{supplier_product.product.name} updated.", status: :see_other
    else
      redirect_to @supplier, alert: supplier_product.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy
    @supplier.supplier_products.find(params[:id]).destroy
    redirect_to @supplier, notice: "Removed.", status: :see_other
  end

  private
    def set_supplier
      @supplier = Current.account.suppliers.find(params[:supplier_id])
    end

    def supplier_product_params
      params.expect(supplier_product: %i[ supplier_sku cost lead_time_days min_order_quantity preferred ])
    end
end
