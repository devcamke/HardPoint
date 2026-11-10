class AccountBackupsController < ApplicationController
  include OwnerOnly, ActiveStorage::Streaming
  refuse_while_impersonated back_to: -> { account_data_path(anchor: "backups") }, only: :show
  rate_limit to: 5, within: 1.hour, only: :create, with: -> { redirect_to account_data_path(anchor: "backups"), alert: "Several backups were made in the last hour; try again later." }

  def create
    backup = Current.account.account_backups.new(kind: "manual", requested_by: Current.user)
    if backup.save
      Current.account.track_event "backup_requested"
      redirect_to account_data_path(anchor: "backups"), notice: "Backing up now. Every owner is emailed when it's done, usually within a few minutes.", status: :see_other
    else
      redirect_to account_data_path(anchor: "backups"), alert: backup.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def show
    backup = Current.account.account_backups.find(params[:id])
    return redirect_to(account_data_path(anchor: "backups"), alert: "That backup is no longer available.") unless backup.downloadable?

    Current.account.track_event "backup_downloaded", taken_at: backup.created_at.iso8601
    send_blob_stream backup.file.blob, disposition: :attachment
  end

  def destroy
    backup = Current.account.account_backups.find(params[:id])
    if backup.downloadable?
      backup.expire!
      Current.account.track_event "backup_deleted", taken_at: backup.created_at.iso8601
    end
    redirect_to account_data_path(anchor: "backups"), notice: "Backup deleted.", status: :see_other
  end
end
