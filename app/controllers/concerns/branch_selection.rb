# Stock screens work on one branch at a time. The choice is remembered for the session.
module BranchSelection
  extend ActiveSupport::Concern

  included do
    helper_method :selected_branch, :branches_for_selection
  end

  private
    def selected_branch
      @selected_branch ||= find_selected_branch.tap { |branch| session[:branch_id] = branch&.id }
    end

    def find_selected_branch
      branches = Current.account.branches
      branches.find_by(id: params[:branch_id]) || branches.find_by(id: session[:branch_id]) || branches.alphabetically.first
    end

    def branches_for_selection
      Current.account.branches.alphabetically
    end
end
