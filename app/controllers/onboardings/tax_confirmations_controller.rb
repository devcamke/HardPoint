class Onboardings::TaxConfirmationsController < ApplicationController
  before_action :ensure_can_manage_account

  def create
    Current.account.update!(taxes_confirmed_at: Time.current)
    redirect_to onboarding_path, notice: "Tax rates checked.", status: :see_other
  end
end
