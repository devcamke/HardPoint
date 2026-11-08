class Admin::DatabasesController < Admin::BaseController
  def show
    @health = DatabaseHealth.new
    @platform = PlatformHealth.check
    @integrity = IntegrityCheck.last
  end
end
