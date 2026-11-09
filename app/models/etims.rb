# KRA eTIMS through the OSCU API: each branch's online control unit signs every sale and credit
# note, and receipts carry the signature and a QR code customers can check with KRA.
module Etims
  # KRA's tax types: A exempt, B standard 16%, C zero-rated, D non-VAT, E 8%.
  TAX_TYPES = { "A" => "Exempt", "B" => "16% VAT", "C" => "Zero-rated", "D" => "Non-VAT", "E" => "8% VAT" }.freeze

  PAYMENT_TYPES = { "cash" => "01", "on_account" => "02", "card" => "05", "mobile_money" => "06", "airtel_money" => "06", "deposit" => "07", "foreign_cash" => "01", "points" => "07" }.freeze

  def self.table_name_prefix
    "etims_"
  end

  # The tax type for a line or product: the code on the tax rate it was sold under (exempt and zero-rated
  # are both 0%, so the percentage alone can't tell them apart); failing that, the shop's rate with that
  # percentage; failing that, KRA's usual type for the percentage.
  def self.tax_type_for(account, rate, tax_rate: nil)
    tax_rate&.etims_code.presence ||
      account.tax_rates.find { _1.rate.to_d == rate.to_d }&.etims_code.presence ||
      { 16 => "B", 8 => "E", 0 => "C" }.fetch(rate.to_d.to_i, "B")
  end
end
