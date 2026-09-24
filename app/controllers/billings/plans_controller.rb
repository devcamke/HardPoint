class Billings::PlansController < ApplicationController
  include BillingScoped

  def update
    if Current.account.change_plan(params[:plan])
      redirect_to billing_path, notice: "You're on the #{Current.account.subscription_plan.name} plan. The new price applies from the next invoice.", status: :see_other
    else
      redirect_to billing_path, alert: Current.account.errors.full_messages.to_sentence, status: :see_other
    end
  end
end
