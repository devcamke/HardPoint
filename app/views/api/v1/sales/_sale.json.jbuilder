json.extract! sale, :id, :receipt_number, :status, :branch_id, :customer_id, :customer_order_id
json.register sale.register&.name
json.cashier sale.cashier&.name
json.extract! sale, :subtotal_cents, :discount_cents, :tax_cents, :total_cents, :completed_at, :voided_at
json.lines sale.lines do |line|
  json.extract! line, :id, :product_id
  json.sku line.product.sku
  json.description line.description
  json.quantity line.quantity.to_s("F")
  json.tax_rate line.tax_rate.to_s("F")
  json.extract! line, :unit_price_cents, :discount_cents, :total_cents, :tax_cents, :serial_number
end
json.payments sale.payments do |payment|
  json.extract! payment, :tender, :amount_cents, :reference
end
json.extract! sale, :created_at, :updated_at
