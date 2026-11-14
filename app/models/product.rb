class Product < ApplicationRecord
  include AccountOwned, Eventable, Monetary, Pricing, Stockable, CutToLength, Searchable, Barcoded, Purchasing, Labelling, PublishesWebhooks

  # Raised when a sale or transfer would have to take stock from an expired batch.
  ExpiredStock = Class.new(StandardError)
  # Raised when a sale would take more than is on the shelf: stock can't be sold below zero.
  OutOfStock = Class.new(StandardError)
  # Raised when a sale needs a piece longer than any length or offcut on the rack, though there's enough in all.
  NoPieceLongEnough = Class.new(OutOfStock)
  publishes_webhooks "product"
  tracks_lifecycle

  belongs_to :category, optional: true
  belongs_to :brand, optional: true
  belongs_to :unit
  belongs_to :tax_rate, optional: true

  has_many :product_units, dependent: :destroy
  has_many :kit_components, foreign_key: :kit_id, dependent: :destroy, inverse_of: :kit
  has_many :components, through: :kit_components
  has_many :price_list_items, dependent: :destroy
  has_one_attached :image
  IMAGE_TYPES = %w[ image/jpeg image/png image/webp image/gif ].freeze
  IMAGE_MAX_SIZE = 5.megabytes
  validate if: -> { image.attached? && attachment_changes["image"] } do
    errors.add :image, "must be a photo (JPEG, PNG, WebP or GIF)" unless image.content_type.in?(IMAGE_TYPES)
    errors.add :image, "must be smaller than #{IMAGE_MAX_SIZE / 1.megabyte} MB" if image.byte_size > IMAGE_MAX_SIZE
  end

  money_attribute :cost, :price

  normalizes :sku, with: ->(sku) { sku.strip.upcase }
  normalizes :name, with: ->(name) { name.squish }

  validates :name, presence: true
  validates :sku, presence: true, uniqueness: { scope: :account_id }
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :cost_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :reorder_level, numericality: { greater_than_or_equal_to: 0 }
  validates_same_account :category, :brand, :unit, :tax_rate

  # Changing how a product is counted while a branch holds some would leave phantom stock: 50 bags
  # that now read as 50 pieces, a kit with stock of its own, or a service with stock nobody can sell.
  validate on: :update, if: -> { unit_id_changed? || track_stock_changed? || kit_changed? } do
    stocked = stock_levels.where.not(quantity: 0).includes(:branch).map { _1.branch.name }.sort
    errors.add :base, "#{name} has stock at #{stocked.to_sentence}, so its unit, stock tracking and kit setting can't change; adjust the stock to zero first" if stocked.any?
  end

  before_validation { self.sku = "P#{SecureRandom.alphanumeric(7).upcase}" if sku.blank? }
  before_save { self.track_stock = false if kit? }
  # KRA keeps the name and tax type a control unit registered, so a change is sent again.
  after_update_commit -> { Etims::ItemUpdateJob.perform_later(self) if Etims::ItemRegistration.exists?(product: self) },
    if: -> { saved_change_to_name? || saved_change_to_tax_rate_id? }

  scope :active, -> { where(active: true) }
  scope :alphabetically, -> { order(:name) }

  def to_s
    name
  end

  def quantity_allowed?(quantity)
    unit.valid_quantity?(quantity)
  end
end
