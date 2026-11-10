# Which product is each of the material calculator's materials, set once by whoever looks after the catalogue.
class MaterialProductsController < ApplicationController
  before_action :ensure_can_manage_catalogue

  def edit
    @mappings = Current.account.material_products.includes(:product, :product_unit).index_by(&:material)
  end

  def update
    rows = params.fetch(:materials, {}).permit(MaterialCalculator::MATERIALS.keys.to_h { [ _1, %i[ product_code product_unit_id factor ] ] }).to_h
    @mappings = Current.account.material_products.includes(:product, :product_unit).index_by(&:material)
    @problems = {}

    MaterialProduct.transaction do
      rows.each do |material, row|
        mapping = @mappings[material] || Current.account.material_products.new(material: material)
        code = row["product_code"].to_s.strip
        if code.blank?
          mapping.destroy if mapping.persisted?
          @mappings.delete(material)
          next
        end
        product = Current.account.products.active.find_by_code(code) || Current.account.products.active.find_by(name: code)
        next @problems[material] = "No product with SKU, barcode or name “#{code}”" unless product

        mapping.assign_attributes(product: product, factor: row["factor"].presence || 1,
          product_unit: product.product_units.find_by(id: row["product_unit_id"]))
        mapping.save ? @mappings[material] = mapping : @problems[material] = mapping.errors.full_messages.to_sentence
      end
      raise ActiveRecord::Rollback if @problems.any?
    end

    if @problems.any?
      flash.now[:alert] = "Some materials couldn't be linked; nothing was saved."
      render :edit, status: :unprocessable_entity
    else
      redirect_to new_material_estimate_path, notice: "Materials linked to your products."
    end
  end
end
