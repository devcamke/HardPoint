# Accepts every reorder level the branch's history suggests (Stock › Reorder), in one go.
class SuggestedReorderLevelsController < ApplicationController
  before_action :ensure_can_manage_catalogue

  def create
    branch = visible_branches.find(params[:branch_id])
    rows = ReorderSuggestion.new(Current.account, branch).rows.select(&:suggested_level)
    StockLevel.transaction do
      rows.each do |row|
        row.product.stock_levels.create_or_find_by!(account: Current.account, branch: branch).update!(reorder_level: row.suggested_level)
      end
    end
    Current.account.track_event "reorder_levels_suggested", branch: branch.name, products: rows.size
    redirect_to reorder_list_path(branch_id: branch.id), notice: "#{branch.name} now reorders #{helpers.pluralize(rows.size, "product")} at the levels its sales suggest."
  end
end
