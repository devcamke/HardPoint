# The owner's "Set up your shop" checklist.
class OnboardingsController < ApplicationController
  before_action :ensure_can_manage_account

  def show
    @onboarding = Onboarding.new(Current.account)
  end
end
