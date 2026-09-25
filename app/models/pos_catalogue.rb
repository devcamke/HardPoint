# Everything a till needs to keep selling offline: its own details, the active catalogue with
# retail prices, pack sizes, barcodes and stock at its branch, customers with their price lists,
# and promotions running now or starting within PROMOTION_DAYS (the till checks the dates on the
# day it sells, so a snapshot taken before a promotion starts still applies it). In as few queries
# as possible.
class PosCatalogue
  PROMOTION_DAYS = 14
  def initialize(shift:, user:)
    @shift = shift
    @user = user
    @account = shift.account
    @branch = shift.branch
  end

  # Changes whenever anything in it could have: products, packs, barcodes, stock, the till's shift or cashier.
  def version
    stamps = [ @account.products.maximum(:updated_at), @account.products.count, @account.product_units.maximum(:updated_at),
               @account.barcodes.maximum(:id), @account.barcodes.count, @account.stock_levels.where(branch: @branch).maximum(:updated_at),
               @account.customers.maximum(:updated_at), @account.customers.count, @account.price_list_items.maximum(:updated_at), @account.price_list_items.count,
               @account.promotions.maximum(:updated_at), @account.promotions.count, Date.current,
               @account.updated_at, @shift.id, @shift.status, @user.id ]
    # Times to the microsecond, so two changes within the same second still make a new version.
    Digest::SHA256.hexdigest(stamps.map { _1.respond_to?(:iso8601) && !_1.is_a?(Date) ? _1.iso8601(6) : _1.to_s }.join("|")).first(20)
  end

  def as_json(*)
    { version: version, generated_at: Time.current.iso8601, till: till, products: products, customers: customers, price_lists: price_lists, promotions: promotions }
  end

  private
    def till
      register = @shift.register
      { account_name: @account.name, currency: @account.currency, time_zone: ActiveSupport::TimeZone[@account.time_zone].tzinfo.name, receipt_footer: @account.receipt_footer, max_discount_percent: @account.max_cashier_discount_percent.to_f,
        branch_id: @branch.id, branch_name: @branch.name, branch_code: @branch.code, branch_address: @branch.address, branch_phone: @branch.phone,
        register_id: register.id, register_name: register.name, print_mode: register.print_mode, printer_name: register.printer_name, receipt_width: register.receipt_width,
        shift_id: @shift.id, cashier_id: @user.id, cashier_name: @user.name,
        paybill: @account.mpesa_shortcodes.for_branch(@branch)&.label }
    end

    def products
      scope = @account.products.active.where(serialized: false)
      barcodes = @account.barcodes.where(product_unit_id: nil).group(:product_id).pluck(:product_id, Arel.sql("array_agg(code)")).to_h
      pack_barcodes = @account.barcodes.where.not(product_unit_id: nil).group(:product_unit_id).pluck(:product_unit_id, Arel.sql("array_agg(code)")).to_h
      stock = @account.stock_levels.where(branch: @branch).pluck(:product_id, :quantity).to_h
      units = @account.units.to_h { [ _1.id, _1 ] }
      packs = @account.product_units.includes(:unit).group_by(&:product_id)
      default_rate = @account.tax_rates.find_by(default: true)&.rate || 0
      rates = @account.tax_rates.pluck(:id, :rate).to_h
      # Retail quantity breaks; customers' price lists come separately (price_lists).
      breaks = @account.price_list_items.where(price_list_id: nil).pluck(:product_id, :min_quantity, :price_cents)
        .group_by(&:first).transform_values { |rows| rows.map { |_, minimum, price| [ minimum.to_f, price ] } }

      scope.order(:name).pluck(:id, :name, :sku, :price_cents, :unit_id, :tax_rate_id, :quick_pick, :track_stock, :kit, :category_id).map do |id, name, sku, price, unit_id, tax_rate_id, quick_pick, track_stock, kit, category_id|
        unit = units[unit_id]
        { id: id, name: name, sku: sku, price_cents: price, category_id: category_id, tax_rate: (rates[tax_rate_id] || default_rate).to_f, unit: unit.abbreviation, fractional: unit.fractional?,
          quick_pick: quick_pick, stock: (stock[id]&.to_f if track_stock && !kit), barcodes: barcodes.fetch(id, []), breaks: breaks.fetch(id, []),
          packs: packs.fetch(id, []).map { |pack| { id: pack.id, name: pack.to_s, quantity: pack.quantity.to_f, price_cents: pack.effective_price_cents,
                                                    unit: pack.unit.abbreviation, barcodes: pack_barcodes.fetch(pack.id, []) } } }
      end
    end

    # Named customers, so sales can be in their name (for their prices and loyalty points) offline.
    def customers
      price_list_names = @account.price_lists.pluck(:id, :name).to_h
      @account.customers.order(:name).pluck(:id, :name, :phone, :price_list_id).map do |id, name, phone, price_list_id|
        { id: id, name: name, phone: phone, price_list_id: price_list_id, price_list_name: price_list_names[price_list_id] }
      end
    end

    # { price list id => { product id => [ [ minimum quantity, price ] ] } }
    def price_lists
      @account.price_list_items.where.not(price_list_id: nil).pluck(:price_list_id, :product_id, :min_quantity, :price_cents)
        .group_by(&:first).transform_values do |rows|
          rows.group_by(&:second).transform_values { |items| items.map { |_, _, minimum, price| [ minimum.to_f, price ] } }
        end
    end

    def promotions
      today = Date.current
      @account.promotions.where(active: true).where(ends_on: today..).where(starts_on: ..(today + PROMOTION_DAYS)).for_branch(@branch).order(:id).map do |promotion|
        promotion.slice(:id, :name, :kind, :product_ids, :category_ids).merge(offer: promotion.offer, starts_on: promotion.starts_on.iso8601, ends_on: promotion.ends_on.iso8601,
          percent_off: promotion.percent_off&.to_f, buy_quantity: promotion.buy_quantity&.to_f, free_quantity: promotion.free_quantity&.to_f)
      end
    end
end
