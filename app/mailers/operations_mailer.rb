# To whoever runs HardPoint (ALERTS_EMAIL): something broke, or a platform check is failing (Alerts).
class OperationsMailer < ApplicationMailer
  def alert
    @body = params[:body]
    mail to: Alerts.email, subject: "[HardPoint #{Rails.configuration.x.environment_name}] #{params[:subject]}"
  end
end
