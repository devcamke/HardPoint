class Admin::Accounts::PlansController < Admin::BaseController
  include Admin::AccountScoped

  def update
    if @account.change_plan(params[:plan], by: nil)
      back_to_account notice: "#{@account.name} is on the #{@account.subscription_plan.name} plan."
    else
      back_to_account alert: @account.errors.full_messages.to_sentence
    end
  end
end
