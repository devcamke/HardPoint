# A sample receipt to check the printer's paper width, and the owner saying it printed properly.
class Onboardings::TestReceiptsController < ApplicationController
  before_action :ensure_can_manage_account

  def show
    @branch = Current.account.branches.alphabetically.first
    render layout: "receipt"
  end

  def create
    Current.account.update!(test_receipt_printed_at: Time.current)
    redirect_to onboarding_path, notice: "Printer checked.", status: :see_other
  end
end
