# Safaricom M-Pesa through the Daraja API: prompts to pay sent to a customer's phone from the
# till (STK push), and payments made straight to a shop's Paybill or Till (C2B).
module Mpesa
  def self.table_name_prefix
    "mpesa_"
  end
end
