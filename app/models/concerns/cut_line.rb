# A line of a sale or an order for a product cut to length (Product::CutToLength): cut_length is the length of each
# piece, and the quantity stays the total, so "3 × 2.5 m" is a quantity of 7.5.
module CutLine
  extend ActiveSupport::Concern

  included do
    before_validation { self.cut_length = nil unless product&.cut_to_length? && product_unit_id.nil? && cut_length.to_d.positive? }
    validate :cut_from_a_length
  end

  # How many pieces the line is, when its quantity is a whole number of them.
  def pieces
    count, rest = quantity.divmod(cut_length) if cut_length.to_d.positive? && quantity
    count.to_i if rest&.zero?
  end

  # "3 × 2.5 m"
  def cut_words
    "#{pieces} × #{product.length_words(cut_length)}" if pieces
  end

  private
    def cut_from_a_length
      return unless cut_length && product&.cut_to_length?

      if cut_length > product.stock_length
        errors.add :base, "#{product.name} comes in lengths of #{product.length_words(product.stock_length)}, so a piece can't be #{product.length_words(cut_length)}"
      elsif quantity && pieces.nil?
        errors.add :base, "#{product.length_words(quantity)} of #{product.name} isn't a whole number of #{product.length_words(cut_length)} pieces"
      end
    end
end
