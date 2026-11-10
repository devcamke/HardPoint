# The platform's audit trail: administrators' sign-ins and the support sign-in links they made.
class Admin::EventsController < Admin::BaseController
  def index
    @events = AdminEvent.newest_first.includes(:user).limit(200)
  end
end
