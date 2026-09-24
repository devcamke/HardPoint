class Onboardings::CompletionsController < ApplicationController
  before_action :ensure_can_manage_account

  def create
    Onboarding.new(Current.account).finish
    redirect_to root_path, notice: "Setup checklist hidden. The guides are always under Help.", status: :see_other
  end
end
