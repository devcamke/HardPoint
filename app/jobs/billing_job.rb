class BillingJob < ApplicationJob
  def perform
    Account.run_billing
  end
end
