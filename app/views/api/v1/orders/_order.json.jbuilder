json.extract! order, :id, :reference, :status, :branch_id, :customer_id
json.customer_name order.customer.name
json.extract! order, :note, :needed_by, :valid_until, :total_cents, :tax_cents
json.lines order.lines do |line|
  json.extract! line, :id, :product_id
  json.sku line.product.sku
  json.description line.description
  json.quantity line.quantity.to_s("F")
  json.extract! line, :unit_price_cents, :total_cents, :tax_cents
end
json.extract! order, :ordered_at, :collected_at, :created_at, :updated_at
