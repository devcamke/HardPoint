# Is the simpler layout working? See Adoption.
class Admin::AdoptionsController < Admin::BaseController
  def show
    across_accounts do
      adoption = Adoption.new
      @cohorts = adoption.first_sale_cohorts
      @features = adoption.features
      @shops_count = adoption.shops_count
      @shortcuts = adoption.shortcuts
      @lost = adoption.lost_requests
    end
  end
end
