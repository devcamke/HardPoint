# Opening the cash drawer without a sale (giving change, a cash drop) is recorded in Activity.
class Pos::DrawerOpeningsController < ApplicationController
  include PosSale
  skip_before_action :set_sale

  def create
    current_till.track_event "drawer_opened", reason: params[:reason].presence || "No sale", shift: current_shift.name
    head :no_content
  end
end
