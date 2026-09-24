json.extract! product, :id, :sku, :name, :description, :price_cents, :active, :track_stock, :kit
json.reorder_level product.reorder_level.to_s("F")
json.category product.category&.name
json.brand product.brand&.name
json.unit product.unit.name
json.tax_rate product.tax_rate&.rate&.to_s("F")
json.barcodes product.barcodes.map(&:code)
json.stock product.stock_levels do |level|
  json.branch_id level.branch_id
  json.quantity level.quantity.to_s("F")
end
json.extract! product, :created_at, :updated_at
