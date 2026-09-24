class Admin::Accounts::TrialExtensionsController < Admin::BaseController
  include Admin::AccountScoped

  def create
    days = params[:days].to_i.clamp(1, 90)
    if @account.extend_trial(days)
      back_to_account notice: "Trial extended to #{I18n.l(@account.trial_ends_at.to_date, format: :long)}."
    else
      back_to_account alert: "Only a shop on its free trial can have the trial extended."
    end
  end
end
