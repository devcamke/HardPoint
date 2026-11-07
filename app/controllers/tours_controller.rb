# The guided tours someone can take in their shop. Each one starts on its own screen, with ?tour=<id> in the address
# (see shared/_guided_tour).
class ToursController < ApplicationController
  def index
    @tours = HelpTour.available_to(current_membership)
  end
end
