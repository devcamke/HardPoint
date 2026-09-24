class Products::UnitsController < ApplicationController
  include ProductScoped
  before_action :ensure_can_manage_catalogue

  def create
    product_unit = @product.product_units.new(params.expect(product_unit: %i[ unit_id quantity price ]).merge(account: Current.account))

    if product_unit.save
      redirect_to_product notice: "Pack size added."
    else
      redirect_to_product alert: product_unit.errors.full_messages.to_sentence
    end
  end

  def destroy
    @product.product_units.find(params[:id]).destroy
    redirect_to_product notice: "Pack size removed."
  end
end
