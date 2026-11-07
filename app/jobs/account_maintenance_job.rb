# Nightly housekeeping across shops: exports past their week, backups past their time (and ones
# whose worker died), and shops whose 30 days of closing are up.
class AccountMaintenanceJob < ApplicationJob
  one_at_a_time

  def perform
    AccountExport.expire_old
    AccountBackup.maintain
    WebhookDelivery.purge_old
    ApiIdempotencyKey.purge_old
    Account.purge_closed
  end
end
