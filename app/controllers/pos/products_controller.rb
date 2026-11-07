class Pos::ProductsController < ApplicationController
  before_action :ensure_can_sell

  # The till's product panel: quick picks, a category's products (with its subcategories'), or search results.
  # Categories are shown as tabs so a touch screen can ring up a sale without a scanner or keyboard.
  def index
    @branch = current_till&.branch
    @categories, subtrees = till_categories
    @category = @categories.find { _1.id.to_s == params[:category_id] } if params[:category_id].present?
    products = Current.account.products.active.includes(:unit, product_units: :unit)

    if params[:query].present?
      @products = products.search(params[:query]).limit(12).to_a
    elsif @category
      @products = products.where(category_id: subtrees[@category.id]).alphabetically.limit(60).to_a
    else
      @products = products.where(quick_pick: true).alphabetically.limit(24).to_a
      @products = products.alphabetically.limit(12).to_a if @products.empty?
    end
  end

  private
    # Top-level categories with something to sell in them or below them, and each one's category ids.
    def till_categories
      categories = Current.account.categories.alphabetically.to_a
      children = categories.group_by(&:parent_id)
      selling = Current.account.products.active.where.not(category_id: nil).distinct.pluck(:category_id).to_set

      subtrees = (children[nil] || []).to_h do |top|
        ids, queue = Set[top.id], [ top.id ]
        while (id = queue.shift)
          (children[id] || []).each { |child| queue << child.id if ids.add?(child.id) }
        end
        [ top.id, ids.to_a ]
      end
      [ (children[nil] || []).select { subtrees[_1.id].any? { |id| selling.include?(id) } }, subtrees ]
    end
end
