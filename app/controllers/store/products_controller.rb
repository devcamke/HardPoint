class Store::ProductsController < Store::BaseController
  include Pagination

  def index
    @query = params[:q].to_s.strip
    @category = storefront.categories.find_by(id: params[:category_id])
    products = storefront.products.includes(:unit, :stock_levels, image_attachment: :blob)
    products = products.where(category: @category) if @category
    products = @query.present? ? products.search(@query) : products.alphabetically
    @products = paginate(products, per_page: 24)
    @categories = storefront.categories
  end

  def show
    @product = storefront.products.includes(:unit, :stock_levels, :category, :brand, :barcodes).find(params[:id])
  end
end
