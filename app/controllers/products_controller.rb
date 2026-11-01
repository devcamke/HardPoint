class ProductsController < ApplicationController
  include ListGrouping

  GROUPINGS = { "category" => "Category", "brand" => "Brand" }.freeze

  before_action :ensure_can_manage_catalogue, except: %i[ index show ]
  before_action :set_product, only: %i[ show edit update destroy ]

  def index
    @products = filtered_products

    respond_to do |format|
      format.html do
        if (@group_by = params[:group_by].presence_in(GROUPINGS.keys))
          @groups = product_groups(@products)
        else
          @products = paginate(@products.includes(:category, :unit))
          @stock = StockLevel.where(branch: selected_branch, product_id: @products.map(&:id)).pluck(:product_id, :quantity).to_h
        end
      end

      format.csv do
        send_data ProductCsv.new(@products, branch: selected_branch, include_costs: current_membership.can_see_costs?).to_csv,
          filename: "#{Current.account.subdomain}-products-#{Date.current}.csv", type: :csv
      end
    end
  end

  def show
    @levels = @product.stock_levels.includes(:branch).index_by(&:branch_id)
    @movements = @product.stock_movements.chronologically.includes(:branch, :creator, :stock_batch).limit(10)
  end

  def new
    @product = Current.account.products.new(unit: Current.account.default_unit, tax_rate: Current.account.default_tax_rate)
  end

  def create
    @product = Current.account.products.new(product_params)

    if save_with_barcode(@product)
      redirect_to @product, notice: "#{@product.name} added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @product.update(product_params)
      redirect_to @product, notice: "Saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @product.destroy
      redirect_to products_path, notice: "#{@product.name} deleted.", status: :see_other
    else
      redirect_to @product, alert: "#{@product.name} has stock history, so it can't be deleted. Mark it inactive instead.", status: :see_other
    end
  end

  private
    def set_product
      @product = Current.account.products.find(params[:id])
    end

    def filtered_products
      products = Current.account.products.search(params[:query])
      products = products.alphabetically if params[:query].blank?
      products = products.where(category_id: none_or_id(Current.account.categories, params[:category_id])) if params[:category_id].present?
      products = products.where(brand_id: none_or_id(Current.account.brands, params[:brand_id])) if params[:brand_id].present?
      products = products.active unless params[:include_inactive] == "1"
      products
    end

    def product_params
      permitted = %i[ name sku description category_id brand_id unit_id tax_rate_id price reorder_level
                      track_stock tracks_batches serialized kit active online image ]
      permitted << :cost if current_membership.can_see_costs?
      params.expect(product: permitted)
    end

    # A manufacturer's barcode can be given when adding a product; otherwise it gets an in-store one.
    def save_with_barcode(product)
      code = params.dig(:product, :barcode).to_s.strip

      Product.transaction do
        product.barcodes.build(account: Current.account, code: code) if code.present?
        product.save or raise ActiveRecord::Rollback
      end
      product.persisted?
    end

    # "none" picks the products without one, e.g. the "No category" group.
    def none_or_id(records, id)
      id == "none" ? nil : records.find(id).id
    end

    def product_groups(products)
      if @group_by == "category"
        names = Current.account.categories.to_h { [ _1.id, _1.full_name ] }
        list_groups(products, :category_id, labels: ->(id) { names[id] || "No category" })
      else
        names = Current.account.brands.pluck(:id, :name).to_h
        list_groups(products, :brand_id, labels: ->(id) { names[id] || "No brand" })
      end
    end
end
