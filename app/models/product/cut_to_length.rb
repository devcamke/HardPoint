# Products that come in lengths and are sold cut: steel bar and pipe in 6 m lengths, cable and chain off a roll.
# The stock level stays the total (in metres); stock_length says how long a full length is, and Offcut rows say
# which of that total is left-over pieces. Product::Cutting decides what each sale is cut from.
module Product::CutToLength
  extend ActiveSupport::Concern

  included do
    has_many :offcuts, dependent: :delete_all

    validates :stock_length, numericality: { greater_than: 0 }, allow_nil: true
    validates :scrap_below, numericality: { greater_than_or_equal_to: 0 }
    validate :cut_from_measured_stock, if: :cut_to_length?

    before_validation { self.scrap_below = 0 if scrap_below.nil? || !cut_to_length? }
    # No longer cut to length: its stock is just a quantity again.
    after_update { offcuts.delete_all if saved_change_to_stock_length? && !cut_to_length? }

    scope :cut_to_length, -> { where.not(stock_length: nil) }
  end

  def cut_to_length?
    stock_length.present?
  end

  # The pieces a quantity is cut as: so many of cut_length each, or full lengths when the line doesn't say, and
  # whatever is left over as one last piece. 14.5 m of a 6 m bar is two full lengths and 2.5 m.
  def pieces_for(quantity, cut_length = nil)
    each = cut_length.to_d.positive? ? cut_length.to_d : stock_length
    whole, rest = quantity.to_d.divmod(each)
    Array.new(whole.to_i, each) + (rest.positive? ? [ rest ] : [])
  end

  def cutting_at(branch)
    Product::Cutting.new(self, branch)
  end

  # What's on the rack at a branch: full lengths, a part length (stock that isn't a whole length or a listed offcut)
  # and the offcuts.
  def lengths_at(branch)
    cutting_at(branch).lengths
  end

  # "2.5 m"
  def length_words(length)
    "#{length.to_d.to_s("F").delete_suffix(".0")} #{unit.abbreviation}"
  end

  private
    def cut_from_measured_stock
      errors.add :stock_length, "is for products sold by a measured unit (metres, feet); #{unit.name.downcase.pluralize} are whole" unless unit&.fractional?
      errors.add :stock_length, "needs stock to be tracked" unless track_stock? && !kit?
      errors.add :stock_length, "can't be combined with batches or serial numbers" if tracks_batches? || serialized?
      errors.add :scrap_below, "must be shorter than the length it comes in" if stock_length.to_d.positive? && scrap_below.to_d >= stock_length
    end
end
