# The till's snapshot of the catalogue, kept on the device for selling offline.
class Pos::CataloguesController < ApplicationController
  include PosSale
  skip_before_action :set_sale

  def show
    catalogue = PosCatalogue.new(shift: current_shift, user: Current.user)
    render json: catalogue if stale?(etag: catalogue.version, public: false)
  end
end
