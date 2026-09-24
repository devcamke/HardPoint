# Kenyan mobile numbers in the international form M-Pesa and SMS providers want: 0722 000 111,
# +254 722 000 111 and 722000111 all become 254722000111.
module PhoneNumber
  COUNTRY_CODE = "254"

  def self.normalize(number)
    digits = number.to_s.gsub(/\D/, "")
    digits = digits.delete_prefix(COUNTRY_CODE) if digits.length == 12 && digits.start_with?(COUNTRY_CODE)
    digits = digits.delete_prefix("0") if digits.length == 10
    "#{COUNTRY_CODE}#{digits}" if digits.match?(/\A[17]\d{8}\z/)
  end

  # 254722000111 → 0722 000 111, for people to read.
  def self.display(number)
    digits = normalize(number) or return number
    "0#{digits[3, 3]} #{digits[6, 3]} #{digits[9, 3]}"
  end
end
