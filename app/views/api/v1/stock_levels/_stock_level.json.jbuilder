json.extract! stock_level, :product_id, :branch_id
json.sku stock_level.product.sku
json.quantity stock_level.quantity.to_s("F")
json.updated_at stock_level.updated_at
