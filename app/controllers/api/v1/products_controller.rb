class Api::V1::ProductsController < Api::V1::BaseController
  before_action :set_product, only: %i[ show update ]

  def index
    scope = Current.account.products.includes(:category, :brand, :unit, :tax_rate, :barcodes, :stock_levels)
    scope = scope.where(active: ActiveModel::Type::Boolean.new.cast(params[:active])) if params.key?(:active)
    scope = scope.where(sku: params[:sku].to_s.strip.upcase) if params[:sku].present?
    @products = paginate(updated_since(scope))
  end

  def show
  end

  def create
    idempotently do
      @product = Current.account.products.new(product_attributes)
      Array(params.dig(:product, :barcodes)).each { |code| @product.barcodes.build(account: Current.account, code: code.to_s.strip) }
      @product.save!
      render :show, status: :created
    end
  end

  def update
    @product.update!(product_attributes)
    render :show
  end

  private
    def set_product
      @product = Current.account.products.find(params[:id])
    end

    # Category and brand by name (made if new), unit and tax rate by name or rate; money in cents.
    def product_attributes
      permitted = params.expect(product: %i[ sku name description price_cents reorder_level active track_stock category brand unit tax_rate ])
      attributes = permitted.except(:category, :brand, :unit, :tax_rate)
      attributes[:category] = named(Current.account.categories, permitted[:category]) if permitted.key?(:category)
      attributes[:brand] = named(Current.account.brands, permitted[:brand]) if permitted.key?(:brand)
      if permitted.key?(:unit)
        attributes[:unit] = Current.account.units.where("lower(name) = :name OR lower(abbreviation) = :name", name: permitted[:unit].to_s.downcase).first ||
          raise(ActionController::BadRequest, "No unit called “#{permitted[:unit]}” in this shop")
      elsif @product.nil?
        attributes[:unit] = Current.account.default_unit
      end
      attributes[:tax_rate] = tax_rate(permitted[:tax_rate]) if permitted.key?(:tax_rate)
      attributes
    end

    def named(scope, name)
      scope.find_or_create_by!(name: name.to_s.squish) if name.present?
    end

    def tax_rate(value)
      return if value.blank?

      Current.account.tax_rates.find_by(rate: value.to_d) || Current.account.tax_rates.find_by("lower(name) = ?", value.to_s.downcase) ||
        raise(ActionController::BadRequest, "No tax rate of “#{value}” in this shop")
    end
end
