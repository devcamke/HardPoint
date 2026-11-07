# Stock › Products › Change prices: pick products, see every new price, then apply (PriceChange).
class PriceChangesController < ApplicationController
  before_action :ensure_can_manage_catalogue

  def new
    @price_change = PriceChange.new(account: Current.account, **price_change_params)
    @preview = params[:price_change].present? && @price_change.valid?
  end

  def create
    @price_change = PriceChange.new(account: Current.account, **price_change_params)

    if (count = @price_change.apply)
      redirect_to products_path, notice: "#{helpers.pluralize(count, "price")} changed: #{@price_change.description}, #{@price_change.change_description}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def price_change_params
      params.fetch(:price_change, {}).permit(:target, :kind, :change, :round_to, :include_packs, :include_price_lists).to_h.symbolize_keys
    end
end
