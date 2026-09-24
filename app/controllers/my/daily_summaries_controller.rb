class My::DailySummariesController < ApplicationController
  allow_while_locked
  def update
    Current.membership.update!(daily_summary: params[:daily_summary] == "true")
    redirect_to my_profile_path, notice: Current.membership.daily_summary? ? "You'll get the daily summary each morning." : "Daily summary turned off.", status: :see_other
  end
end
