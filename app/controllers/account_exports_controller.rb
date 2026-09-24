class AccountExportsController < ApplicationController
  include OwnerOnly, ActiveStorage::Streaming
  rate_limit to: 3, within: 1.hour, only: :create, with: -> { redirect_to account_data_path, alert: "An export was asked for recently; wait for that one." }

  def create
    Current.account.account_exports.create!
    Current.account.track_event "export_requested"
    redirect_to account_data_path, notice: "Preparing the export. We'll email #{Current.user.email_address} when it's ready, usually within a few minutes.", status: :see_other
  end

  def show
    export = Current.account.account_exports.find(params[:id])
    return redirect_to(account_data_path, alert: "That export has expired; make a new one.") unless export.downloadable?

    send_blob_stream export.file.blob, disposition: :attachment
  end
end
