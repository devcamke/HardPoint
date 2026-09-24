class Admin::DatabasesController < Admin::BaseController
  def show
    @health = DatabaseHealth.new
  end
end
