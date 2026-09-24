# What HardPoint charges shops: monthly invoices per plan, paid by M-Pesa (a prompt to the owner's
# phone, on the platform's own Paybill) or by card through Paystack.
module Billing
  def self.table_name_prefix
    "billing_"
  end

  # The platform's own details, for its invoices.
  def self.company
    Rails.application.credentials.dig(:billing, :company) || { name: "HardPoint Ltd", address: "Nairobi, Kenya", tax_pin: nil, email: "billing@hardpoint.app" }
  end
end
