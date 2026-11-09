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
          @levels = StockLevel.where(branch: selected_branch, product_id: @products.map(&:id)).index_by(&:product_id)
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
    # "Add and start another" keeps the category and unit, for entering a shelf of similar things.
    @product = Current.account.products.new(unit: Current.account.units.find_by(id: params[:unit_id]) || Current.account.default_unit,
      category: Current.account.categories.find_by(id: params[:category_id]), tax_rate: Current.account.default_tax_rate)
  end

  def create
    @product = Current.account.products.new(product_params)

    if save_with_barcode(@product)
      notice = "#{@product.name} added#{" with #{helpers.quantity(@product.stock_at(selected_branch), @product.unit)} at #{selected_branch.name}" if @product.stock_at(selected_branch).positive?}."
      if params[:add_another]
        UsageCount.record("product_add_another")
        redirect_to new_product_path(category_id: @product.category_id, unit_id: @product.unit_id), notice: notice
      else
        redirect_to @product, notice: notice
      end
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
    # Opening stock at the current branch goes through the stock ledger like any other adjustment.
    def save_with_barcode(product)
      code = params.dig(:product, :barcode).to_s.strip

      Product.transaction do
        product.barcodes.build(account: Current.account, code: code) if code.present?
        product.save or raise ActiveRecord::Rollback
        record_opening_stock(product) or raise ActiveRecord::Rollback
      end
      product.persisted? && product.errors.empty?
    end

    def record_opening_stock(product)
      quantity = params.dig(:product, :opening_stock).presence&.then { BigDecimal(_1, exception: false) }
      return true if quantity.nil? || quantity.zero? || !product.track_stock? || !current_membership.can_manage_stock?

      adjustment = Current.account.stock_adjustments.new(product: product, branch: selected_branch, reason: "opening", quantity: quantity)
      return true if adjustment.save

      adjustment.errors.each { product.errors.add :base, "Opening stock #{_1.message}" }
      false
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
