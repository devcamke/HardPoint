class Pos::ProductsController < ApplicationController
  before_action :ensure_can_sell

  def index
    @branch = current_till&.branch
    @products = params[:query].present? ? Current.account.products.active.search(params[:query]).includes(:unit, product_units: :unit).limit(12).to_a : []

    if params[:query].blank?
      @quick_picks = Current.account.products.active.where(quick_pick: true).alphabetically.includes(:unit, product_units: :unit).limit(24).to_a
      @quick_picks = Current.account.products.active.alphabetically.includes(:unit, product_units: :unit).limit(12).to_a if @quick_picks.empty?
    end
  end
end
