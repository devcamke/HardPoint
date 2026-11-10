# Which of the owner's emails you get: the daily and weekly summaries, and the instant alerts.
class My::EmailsController < ApplicationController
  allow_while_locked

  EMAILS = {
    "daily_summary" => [ "You'll get the daily summary each morning.", "Daily summary turned off." ],
    "weekly_summary" => [ "You'll get the weekly summary each Monday.", "Weekly summary turned off." ],
    "alert_emails" => [ "You'll be emailed straight away when something needs you.", "Alerts turned off." ]
  }.freeze

  def update
    email = params[:email].presence_in(EMAILS.keys) or return head(:unprocessable_entity)
    on = params[:on] == "true"
    Current.membership.update!(email => on)
    redirect_to my_profile_path, notice: EMAILS[email][on ? 0 : 1], status: :see_other
  end
end
