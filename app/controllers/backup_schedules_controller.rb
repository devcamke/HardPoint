# The owners' choice of how often the shop is backed up, how many to keep, and which emails they get.
class BackupSchedulesController < ApplicationController
  include OwnerOnly

  def update
    if Current.account.update(params.expect(account: %i[ backup_frequency backups_kept backup_notifications ]))
      redirect_to account_data_path(anchor: "backups"), notice: "Backup settings saved.", status: :see_other
    else
      redirect_to account_data_path(anchor: "backups"), alert: Current.account.errors.full_messages.to_sentence, status: :see_other
    end
  end
end
