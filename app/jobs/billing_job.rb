class BillingJob < ApplicationJob
  one_at_a_time

  def perform
    Account.run_billing
  end
end
