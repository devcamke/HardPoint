# The public site's pages about one job or one market (see SolutionPage), at short addresses like /kra-etims-pos.
class SolutionsController < ApplicationController
  allow_unscoped_access
  allow_unauthenticated_access
  layout "marketing"

  def show
    @page = SolutionPage.find(params[:id])
    @plans = Plan.all
  end
end
