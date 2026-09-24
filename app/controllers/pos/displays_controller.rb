# The customer-facing display: a second screen (or tablet) beside the till, showing the cart
# as it's rung up. It's fed by the till in the same browser, so it works offline too.
class Pos::DisplaysController < ApplicationController
  include PosSale
  skip_before_action :set_sale

  layout "display"

  def show
  end
end
