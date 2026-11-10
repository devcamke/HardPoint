# Naming the fundi who brought the customer (index finds them, update puts them on the sale).
class Pos::FundisController < ApplicationController
  include PosSale
  skip_before_action :require_till_and_shift, :set_sale, only: :index

  def index
    @fundis = Current.account.fundis.active.search(params[:query]).alphabetically.limit(10)
  end

  def update
    fundi = params[:fundi_id].presence && Current.account.fundis.active.find(params[:fundi_id])
    @sale.change_fundi(fundi)
    render_cart message: fundi ? "Brought by #{fundi.name}" : "No fundi on this sale"
  rescue ActiveRecord::RecordInvalid, ArgumentError => error
    render_cart alert: error.message, status: :unprocessable_entity
  end
end
