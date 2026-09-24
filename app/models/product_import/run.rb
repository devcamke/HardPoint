# Writes a checked import in batches with upserts, so tens of thousands of rows take minutes,
# not hours. Stock is set through the ledger: new stock levels are bulk-inserted with their
# opening movements; existing ones go through Product#move_stock so every change is recorded.
class ProductImport::Run
  def initialize(import)
    @import = import
    @account = import.account
    @lookups = ProductImport::Lookups.new(@account)
    @categories = @account.categories.to_h { [ _1.name.downcase, _1.id ] }
    @brands = @account.brands.to_h { [ _1.name.downcase, _1.id ] }
  end

  def perform
    return unless @import.importing?

    @import.rows.each.with_index(2).each_slice(ProductImport::BATCH_SIZE) do |batch|
      rows = batch.map { |data, line| ProductImport::Row.new(line, data, @lookups) }
      ActiveRecord::Base.transaction { import_batch(rows) }
    end

    @import.update!(status: :completed)
    @import.track_event "completed", creator: @import.creator, created: @import.created_count, updated: @import.updated_count
  end

  private
    def import_batch(rows)
      now = Time.current
      records = rows.map do |row|
        row.attributes.merge(account_id: @account.id, sku: row.sku || "P#{SecureRandom.alphanumeric(7).upcase}",
          category_id: find_or_create(:categories, row.category_name), brand_id: find_or_create(:brands, row.brand_name))
      end

      ids = Product.upsert_all(records, unique_by: %i[ account_id sku ], update_only: updatable_columns, returning: %i[ id sku ], record_timestamps: true)
        .to_h { [ _1["sku"], _1["id"] ] }
      rows.zip(records).each { |row, record| row.attributes[:sku] = record[:sku] }

      import_barcodes(rows, ids, now)
      import_stock(rows, ids, now)
    end

    COLUMNS_BY_HEADER = { "name" => :name, "price" => :price_cents, "cost" => :cost_cents, "unit" => :unit_id, "tax_rate" => :tax_rate_id,
                          "reorder_level" => :reorder_level, "active" => :active, "category" => :category_id, "brand" => :brand_id }.freeze

    # Existing products only change in the columns the spreadsheet actually has.
    def updatable_columns
      @updatable_columns ||= COLUMNS_BY_HEADER.slice(*@import.rows.headers.compact).values
    end

    def find_or_create(table, name)
      return if name.blank?

      cache = table == :categories ? @categories : @brands
      cache[name.downcase] ||= @account.public_send(table).create_or_find_by!(name: name).id
    end

    def import_barcodes(rows, ids, now)
      given = rows.filter_map { |row| { account_id: @account.id, product_id: ids[row.sku], code: row.barcode, created_at: now, updated_at: now } if row.barcode }
      Barcode.insert_all(given, unique_by: %i[ account_id code ]) if given.any?

      # Products that still have no barcode get an in-store EAN-13, as they would when added by hand.
      without = ids.values - Barcode.where(product_id: ids.values).distinct.pluck(:product_id)
      internal = without.map { |id| { account_id: @account.id, product_id: id, code: Product.internal_barcode_for(id), created_at: now, updated_at: now } }
      Barcode.insert_all(internal, unique_by: %i[ account_id code ]) if internal.any?
    end

    def import_stock(rows, ids, now)
      return unless @import.branch

      with_stock = rows.select(&:stock).to_h { [ ids[_1.sku], _1.stock ] }
      existing = StockLevel.where(branch: @import.branch, product_id: with_stock.keys).index_by(&:product_id)

      new_levels = with_stock.reject { |id, quantity| existing.key?(id) || quantity.zero? }
      if new_levels.any?
        StockLevel.insert_all(new_levels.map { |id, quantity| { account_id: @account.id, branch_id: @import.branch_id, product_id: id, quantity: quantity, created_at: now, updated_at: now } })
        StockMovement.insert_all(new_levels.map { |id, quantity|
          { account_id: @account.id, branch_id: @import.branch_id, product_id: id, quantity: quantity, balance: quantity,
            reason: "opening", source_type: "ProductImport", source_id: @import.id, creator_id: @import.creator_id, created_at: now }
        })
      end

      Product.where(id: existing.keys).each do |product|
        change = with_stock[product.id] - existing[product.id].quantity
        next if change.zero?
        product.move_stock(branch: @import.branch, quantity: change, reason: "correction", source: @import, note: "Spreadsheet import", creator: @import.creator)
      end
    end
end
