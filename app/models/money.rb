# Formatting for plain-text messages (views use the money helper).
module Money
  def self.format(cents, currency: Current.account&.currency)
    ActiveSupport::NumberHelper.number_to_currency(cents.to_i / 100.0, unit: "#{currency} ", format: "%u%n", negative_format: "-%u%n")
  end
end
