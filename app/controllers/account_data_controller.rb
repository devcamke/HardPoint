class AccountDataController < ApplicationController
  include OwnerOnly

  def show
    @exports = Current.account.account_exports.chronologically.includes(:requested_by).limit(5)
  end
end
