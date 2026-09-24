# Ending the trial early: the first month's invoice now.
class Billings::SubscriptionStartsController < ApplicationController
  include BillingScoped

  def create
    invoice = Current.account.start_subscription_now
    redirect_to billing_path, notice: "Invoice #{invoice.number} is ready to pay.", status: :see_other
  end
end
