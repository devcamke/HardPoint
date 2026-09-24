class Api::V1::BranchesController < Api::V1::BaseController
  def index
    @branches = Current.account.branches.alphabetically
  end
end
