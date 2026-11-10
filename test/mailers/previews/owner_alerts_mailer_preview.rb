# Preview at http://demo.localhost:3000/rails/mailers/owner_alerts_mailer (each needs one in the shop's history).
class OwnerAlertsMailerPreview < ActionMailer::Preview
  def shift_short
    preview(:shift_short) { |account| account.shifts.closed.to_a.select { _1.variance_cents.to_i.negative? }.min_by(&:variance_cents) || account.shifts.closed.last }
  end

  def large_void
    preview(:large_void) { |account| account.sales.voided.order(:total_cents).last }
  end

  def count_loss
    preview(:count_loss) { |account| account.stock_counts.approved.last }
  end

  private
    def preview(alert)
      account = Account.first
      Current.account = account
      record = yield(account) or raise "Nothing in #{account.name}'s history to preview this with"
      OwnerAlertsMailer.with(record: record, recipients: account.alert_recipients, by: nil).public_send(alert)
    end
end
