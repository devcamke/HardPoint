class Api::V1::ShopsController < Api::V1::BaseController
  def show
    @account = Current.account
    @branches = Current.account.branches.alphabetically
  end
end
