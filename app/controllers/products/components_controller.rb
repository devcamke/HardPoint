class Products::ComponentsController < ApplicationController
  include ProductScoped
  before_action :ensure_can_manage_catalogue

  def create
    component = @product.kit_components.new(account: Current.account, quantity: params.dig(:kit_component, :quantity),
      component: Current.account.products.find_by_code(params.dig(:kit_component, :product_code)))

    if component.component.nil?
      redirect_to_product alert: "No product with barcode or SKU “#{params.dig(:kit_component, :product_code)}”."
    elsif component.save
      redirect_to_product notice: "#{component.component.name} added to the kit."
    else
      redirect_to_product alert: component.errors.full_messages.to_sentence
    end
  end

  def destroy
    @product.kit_components.find(params[:id]).destroy
    redirect_to_product notice: "Removed from the kit."
  end
end
