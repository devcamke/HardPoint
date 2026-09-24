json.extract! customer, :id, :name, :phone, :email, :tax_pin, :address, :notes, :credit_limit_cents, :payment_terms_days
json.balance_cents customer.balance_cents
json.extract! customer, :created_at, :updated_at
