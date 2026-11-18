# Emails sent the moment something worth stopping for happens: a shift closing short, a completed sale voided, a
# stock count losing more than the owner allows, or stock written off by hand past the day's limit (the amounts are
# on Shop details). Owners and managers get them
# unless they turned them off under My profile; whoever did it isn't told about it.
module Account::OwnerAlerts
  extend ActiveSupport::Concern

  ALERT_ROLES = %w[ owner manager ].freeze
  ALERTS = %i[ shift_short large_void count_loss large_write_off ].freeze

  def alert_recipients(except: nil)
    people = users.where(memberships: { role: ALERT_ROLES, alert_emails: true })
    people = people.where.not(id: except.id) if except
    people.pluck(:email_address)
  end

  # Sent once the change is saved, so the email never describes something that was rolled back.
  def alert_owners(alert, record, by: nil, **details)
    raise ArgumentError, "Unknown alert #{alert}" unless alert.in?(ALERTS)

    recipients = alert_recipients(except: by)
    return if recipients.empty?

    ActiveRecord.after_all_transactions_commit do
      OwnerAlertsMailer.with(record: record, recipients: recipients, by: by&.name, **details).public_send(alert).deliver_later
    end
  end
end
