class Onboardings::CompletionsController < ApplicationController
  before_action :ensure_can_manage_account

  def create
    onboarding = Onboarding.new(Current.account)
    if onboarding.finish
      redirect_to root_path, notice: "Setup checklist hidden. The guides are always under Help.", status: :see_other
    else
      redirect_to onboarding_path, alert: "Not finished yet: #{onboarding.steps_left.map(&:title).to_sentence}.", status: :see_other
    end
  end
end
