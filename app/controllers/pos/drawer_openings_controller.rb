# Opening the cash drawer without a sale (giving change, a cash drop) is recorded in Activity, with why: the till's
# menu offers these reasons. CashierPatterns counts them per cashier, and the shift's page lists them.
class Pos::DrawerOpeningsController < ApplicationController
  include PosSale
  skip_before_action :set_sale

  REASONS = [ "Change for a customer", "Cash drop to the safe", "Checking the float", "Other" ].freeze

  def create
    reason = params[:reason].to_s.in?(REASONS) ? params[:reason] : "No sale"
    current_till.track_event "drawer_opened", reason: reason, shift: current_shift.name, shift_id: current_shift.id
    head :no_content
  end
end
