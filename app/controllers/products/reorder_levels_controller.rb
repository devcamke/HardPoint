# A branch's own reorder level for a product, set on the product's page. Blank goes back to the product's.
class Products::ReorderLevelsController < ApplicationController
  before_action :ensure_can_manage_catalogue

  def update
    product = Current.account.products.find(params[:product_id])
    branch = Current.account.branches.find(params[:branch_id])
    level = product.stock_levels.create_or_find_by!(account: Current.account, branch: branch)

    if level.update(reorder_level: params[:reorder_level].presence)
      notice = level.reorder_level ? "#{branch.name} now reorders #{product.name} at #{helpers.quantity(level.reorder_level, product.unit)}." : "#{branch.name} uses the product's reorder level again."
      redirect_to product, notice: notice
    else
      redirect_to product, alert: "Reorder level #{level.errors[:reorder_level].to_sentence}."
    end
  end
end
