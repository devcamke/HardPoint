module Product::Barcoded
  extend ActiveSupport::Concern

  # EAN-13 numbers starting 20–29 are reserved for in-store use, so products without a
  # manufacturer's barcode get one of those.
  INTERNAL_PREFIX = "20"

  included do
    has_many :barcodes, dependent: :destroy
    after_create :assign_internal_barcode, unless: -> { barcodes.any? }
  end

  class_methods do
    def internal_barcode_for(id)
      digits = INTERNAL_PREFIX + id.to_s.rjust(10, "0")
      digits + ean13_check_digit(digits).to_s
    end

    def ean13_check_digit(twelve_digits)
      sum = twelve_digits.chars.each_with_index.sum { |digit, index| digit.to_i * (index.even? ? 1 : 3) }
      (10 - sum % 10) % 10
    end
  end

  # For labels: a single item's manufacturer barcode if it has one, else its in-store code.
  def primary_barcode
    barcodes.min_by { |barcode| [ barcode.product_unit_id ? 1 : 0, barcode.internal? ? 1 : 0, barcode.id ] }&.code
  end

  private
    def assign_internal_barcode
      barcodes.create! account: account, code: self.class.internal_barcode_for(id)
    end
end
