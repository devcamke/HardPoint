# To each owner of a shop: a backup is ready (unless they asked only to hear about problems), or one failed.
class AccountBackupsMailer < ApplicationMailer
  before_action do
    @backup = params[:backup]
    @account = @backup.account
    @recipient = params[:recipient] # nil for the email to support
    @taken_at = @backup.created_at.in_time_zone(@account.time_zone)
  end

  def succeeded
    mail to: @recipient.email_address, subject: "#{@account.name} is backed up (#{I18n.l(@taken_at, format: :short)})"
  end

  def failed
    mail to: @recipient.email_address, reply_to: Rails.configuration.x.support[:email],
      subject: "Action needed: #{@account.name}'s backup didn't work"
  end

  # To HardPoint support, with what went wrong (owners are told only that it failed).
  def failed_for_support
    mail to: Rails.configuration.x.support[:email], subject: "Backup #{@backup.id} of #{@account.subdomain} failed"
  end
end
