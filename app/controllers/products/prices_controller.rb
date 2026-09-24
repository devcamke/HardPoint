class Products::PricesController < ApplicationController
  include ProductScoped
  before_action :ensure_can_manage_catalogue

  def create
    item = @product.price_list_items.new(params.expect(price_list_item: %i[ price_list_id min_quantity price ]).merge(account: Current.account))

    if item.save
      redirect_to_product notice: "Price added."
    else
      redirect_to_product alert: item.errors.full_messages.to_sentence
    end
  end

  def destroy
    @product.price_list_items.find(params[:id]).destroy
    redirect_to_product notice: "Price removed."
  end
end
