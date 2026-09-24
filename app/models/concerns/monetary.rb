# Money is stored as integer cents (price_cents) and exposed as BigDecimal amounts (price),
# so arithmetic never suffers float rounding.
module Monetary
  extend ActiveSupport::Concern

  class_methods do
    def money_attribute(*names)
      names.each do |name|
        define_method(name) do
          cents = self[:"#{name}_cents"]
          BigDecimal(cents) / 100 if cents
        end

        define_method(:"#{name}=") do |amount|
          self[:"#{name}_cents"] = Monetary.to_cents(amount)
        end
      end
    end
  end

  def self.to_cents(amount)
    return if amount.blank?

    decimal = amount.is_a?(Numeric) ? BigDecimal(amount.to_s) : BigDecimal(amount.to_s.delete(", "), exception: false)
    (decimal * 100).round if decimal
  end
end
