class Airtel::StatusCheckJob < ApplicationJob
  def perform(request)
    request.check_status
  end
end
