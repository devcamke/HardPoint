class Mpesa::StatusCheckJob < ApplicationJob
  def perform(stk_request)
    stk_request.check_status
  end
end
