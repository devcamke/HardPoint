class Admin::Accounts::SuspensionsController < Admin::BaseController
  include Admin::AccountScoped

  def create
    @account.suspend(params[:reason].to_s.strip.first(200))
    back_to_account notice: "#{@account.name} is suspended: its staff can look but not change anything."
  end

  def destroy
    if @account.restore
      back_to_account notice: "#{@account.name} is restored (#{@account.subscription_status.humanize.downcase})."
    else
      back_to_account alert: "#{@account.name} isn't suspended."
    end
  end
end
