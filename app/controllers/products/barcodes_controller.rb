class Products::BarcodesController < ApplicationController
  include ProductScoped
  before_action :ensure_can_manage_catalogue

  def create
    barcode = @product.barcodes.new(params.expect(barcode: %i[ code product_unit_id ]).merge(account: Current.account))

    if barcode.save
      redirect_to_product notice: "Barcode added."
    else
      redirect_to_product alert: barcode.errors.full_messages.to_sentence
    end
  end

  def destroy
    @product.barcodes.find(params[:id]).destroy
    redirect_to_product notice: "Barcode removed."
  end
end
