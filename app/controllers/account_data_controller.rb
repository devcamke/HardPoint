class AccountDataController < ApplicationController
  include OwnerOnly

  def show
    @backups = Current.account.account_backups.chronologically.includes(:requested_by, file_attachment: :blob).limit(30)
    @exports = Current.account.account_exports.chronologically.includes(:requested_by).limit(5)
  end
end
