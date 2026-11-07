# Changing many selling prices at once, when cement or steel goes up: products picked by category (with its
# subcategories), brand or supplier, or all of them, moved by a percentage or an amount, and rounded. Packs
# with their own price and price-list prices for the same products move by the same rule unless left out.
# Each product's change is in its history (the activity log) like any edit.
class PriceChange
  include ActiveModel::Model
  include ActiveModel::Attributes

  SCOPES = %w[ all category brand supplier ].freeze
  KINDS = { "percent" => "By a percentage", "amount" => "By an amount" }.freeze
  ROUNDINGS = { 0 => "Don't round", 100 => "Nearest 1", 500 => "Nearest 5", 1000 => "Nearest 10", 5000 => "Nearest 50" }.freeze

  Row = Data.define(:record, :label, :old_cents, :new_cents)

  # "all", or "category:12", "brand:3", "supplier:7".
  attribute :target, :string
  attribute :kind, :string, default: "percent"
  attribute :change, :decimal
  attribute :round_to, :integer, default: 0
  attribute :include_packs, :boolean, default: true
  attribute :include_price_lists, :boolean, default: true

  attr_accessor :account

  validates :target, presence: { message: "choose which products" }
  validates :scope, inclusion: { in: SCOPES, message: "isn't one HardPoint knows" }, if: -> { target.present? }
  validates :kind, inclusion: { in: KINDS.keys }
  validates :round_to, inclusion: { in: ROUNDINGS.keys }
  validates :change, presence: true, numericality: { other_than: 0 }
  validates :change, numericality: { greater_than: -100, message: "can't take prices down by 100% or more" }, if: -> { kind == "percent" && change }

  def scope = target.to_s.split(":").first
  def scope_id = target.to_s.split(":").second&.to_i

  def products
    products = account.products.active.where("products.price_cents > 0").order(:name)
    case scope
    when "category" then products.where(category_id: category_ids)
    when "brand" then products.where(brand_id: scope_id)
    when "supplier" then products.where(id: account.supplier_products.where(supplier_id: scope_id).select(:product_id))
    else products
    end
  end

  # Every price that would move, with what it is now and what it becomes.
  def rows
    @rows ||= begin
      products = self.products.includes(:product_units, price_list_items: :price_list).to_a
      products.flat_map do |product|
        [ Row.new(product, product.name, product.price_cents, new_price(product.price_cents)) ] +
          (include_packs ? product.product_units.select(&:price_cents).map { Row.new(_1, "#{product.name} (#{_1})", _1.price_cents, new_price(_1.price_cents)) } : []) +
          (include_price_lists ? product.price_list_items.map { Row.new(_1, price_list_label(product, _1), _1.price_cents, new_price(_1.price_cents)) } : [])
      end.reject { _1.old_cents == _1.new_cents }
    end
  end

  def new_price(cents)
    moved = kind == "percent" ? cents * (1 + change.to_d / 100) : cents + change.to_d * 100
    moved = (moved / round_to).round(half: :up) * round_to if round_to.positive?
    [ moved.round, 0 ].max
  end

  def apply
    return false unless valid?

    changed = rows
    ActiveRecord::Base.transaction do
      changed.each { |row| row.record.update!(price_cents: row.new_cents) }
      account.track_event "prices_changed", count: changed.count { _1.record.is_a?(Product) }, scope: description, change: change_description
    end
    changed.size
  end

  def description
    case scope
    when "category" then account.categories.find_by(id: scope_id)&.full_name
    when "brand" then account.brands.find_by(id: scope_id)&.name
    when "supplier" then "#{account.suppliers.find_by(id: scope_id)&.name}'s products"
    else "all products"
    end
  end

  def change_description
    amount = kind == "percent" ? "#{change.to_d.to_s("F").delete_suffix(".0")}%" : Money.format((change.to_d * 100).round, currency: account.currency)
    "#{change.to_d.positive? ? "up" : "down"} #{amount.delete_prefix("-")}"
  end

  private
    # "Bamburi cement 50kg · Contractor", or "· Retail from 50" for a quantity break on the shop's own prices.
    def price_list_label(product, item)
      from = " from #{item.min_quantity.to_d.to_s("F").delete_suffix(".0")}" if item.min_quantity.to_d > 1
      "#{product.name} · #{item.price_list&.name || "Retail"}#{from}"
    end

    def category_ids
      children = account.categories.pluck(:id, :parent_id).group_by(&:last).transform_values { _1.map(&:first) }
      ids, queue = [], [ scope_id ]
      until queue.empty?
        id = queue.shift
        ids << id
        queue.concat(children.fetch(id, []))
      end
      ids
    end
end
