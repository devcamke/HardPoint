# Shows freshly generated recovery codes exactly once, right after two-factor is turned on.
class My::RecoveryCodesController < ApplicationController
  allow_without_two_factor

  def show
    @recovery_codes = session.delete(:new_recovery_codes)
    redirect_to my_profile_path unless @recovery_codes
  end
end
