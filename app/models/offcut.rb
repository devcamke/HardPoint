# A piece left over from cutting a product that comes in lengths (Product::CutToLength): 3.5 m of a 6 m bar, back
# on the rack. The branch's stock level already counts it; this says that part of the stock is one piece this long,
# so the next cut that fits comes from it rather than from a full length.
class Offcut < ApplicationRecord
  include AccountOwned

  belongs_to :branch
  belongs_to :product

  validates :length, numericality: { greater_than: 0 }
  validates_same_account :branch, :product
  validate { errors.add :length, "must be shorter than the #{product.length_words(product.stock_length)} it comes in" if length && product&.stock_length && length >= product.stock_length }

  scope :shortest_first, -> { order(:length, :id) }

  # A piece already on the rack that the list doesn't know about. No stock changes hands: some of what's counted as
  # full lengths (or the part length) is from now on counted as this piece, so there has to be that much unlisted.
  def self.record(product:, branch:, length:)
    offcut = new(account: product.account, product: product, branch: branch, length: length)
    transaction do
      product.stock_levels.where(branch: branch).lock.load
      lengths = product.lengths_at(branch)
      if offcut.valid? && lengths.full.zero? && lengths.part < offcut.length
        offcut.errors.add :base, "Every #{product.unit.name.downcase} of #{product.name} at #{branch.name} is already listed, so there's no #{product.length_words(offcut.length)} piece to add"
      end
      offcut.save if offcut.errors.none?
    end
    offcut
  end

  # Thrown away: it leaves the list and the stock, as cutting waste.
  def scrap(creator: Current.user)
    transaction do
      destroy!
      product.move_stock(branch: branch, quantity: -length, reason: "cutting_waste", note: "#{product.length_words(length)} offcut scrapped", creator: creator)
    end
  end
end
