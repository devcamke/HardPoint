# Nightly housekeeping across shops: exports past their week, and shops whose 30 days of closing are up.
class AccountMaintenanceJob < ApplicationJob
  def perform
    AccountExport.expire_old
    Account.purge_closed
  end
end
