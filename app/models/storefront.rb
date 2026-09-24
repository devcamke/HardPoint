# A shop's public online store at <shop>.hardpoint.app/store: which branches take click-and-collect
# orders, what the store says about itself, and whether customers see how many are in stock.
class Storefront < ApplicationRecord
  include AccountOwned, Eventable
  tracks_lifecycle only: :update

  validates :headline, length: { maximum: 100 }
  validates :intro, length: { maximum: 2_000 }
  validates :collection_note, length: { maximum: 500 }
  validates :contact_phone, length: { maximum: 30 }
  validate { errors.add :collection_branch_ids, "must be this shop's branches" if (collection_branch_ids - account.branches.ids).any? }
  validate { errors.add :base, "Choose at least one branch for collection" if enabled? && collection_branches.none? }

  before_validation { self.collection_branch_ids = Array(collection_branch_ids).compact_blank.map(&:to_i).uniq }

  def self.for(account)
    account.storefront || account.build_storefront
  end

  # Open to browse whenever it's switched on; orders only while the shop can trade.
  def taking_orders?
    enabled? && !account.locked?
  end

  def collection_branches
    account.branches.where(id: collection_branch_ids).alphabetically
  end

  # What's for sale online: active products with a price, not left out of the store.
  def products
    account.products.active.where(online: true).where("products.price_cents > 0")
  end

  def categories
    account.categories.where(id: products.select(:category_id)).order(:name)
  end

  # :available (not stock-tracked, or a kit), :in_stock, :low or :out, with the quantity, from the
  # product's loaded stock levels (preload them for lists).
  def availability(product, branch)
    return [ :available, nil ] if !product.track_stock? || product.kit?

    quantity = product.stock_levels.find { _1.branch_id == branch.id }&.quantity || 0
    status = if quantity <= 0 then :out
    elsif quantity <= product.reorder_level then :low
    else :in_stock
    end
    [ status, quantity ]
  end

  RANK = { available: 0, in_stock: 1, low: 2, out: 3 }.freeze

  # The collection branch where it's easiest to get: [ status, quantity, branch ].
  def best_availability(product, branches = collection_branches.to_a)
    branches.map { |branch| [ *availability(product, branch), branch ] }.min_by { |status, quantity, _| [ RANK[status], -quantity.to_d ] }
  end

  def event_name
    "online store"
  end
end
