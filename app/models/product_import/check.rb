class ProductImport::Check
  PREVIEW_ROWS = 10

  def initialize(import)
    @import = import
    @account = import.account
  end

  def perform
    lookups = ProductImport::Lookups.new(@account)
    problems, preview, skus, barcodes, units = [], [], Hash.new(0), Hash.new(0), {}
    rows_count = 0

    @import.rows.each.with_index(2) do |data, line|
      rows_count += 1
      row = ProductImport::Row.new(line, data, lookups)
      skus[row.sku] += 1 if row.sku
      barcodes[row.barcode] += 1 if row.barcode
      units[row.sku] = row.attributes[:unit_id] if row.sku && data.header?("unit")
      problems << { "line" => line, "messages" => row.problems } unless row.valid?
      preview << row.attributes.slice(:sku, :name).merge(price: row.attributes[:price_cents], stock: row.stock&.to_s("F")) if preview.size < PREVIEW_ROWS
    end

    duplicate_skus = skus.select { |_, count| count > 1 }.keys
    problems << { "line" => nil, "messages" => [ "SKUs used on more than one row: #{duplicate_skus.first(20).join(", ")}" ] } if duplicate_skus.any?
    problems.concat barcode_conflicts(barcodes)
    problems.concat unit_changes(units)

    existing = @account.products.where(sku: skus.keys).count
    @import.update!(status: problems.any? ? :needs_fixing : :ready, rows_count: rows_count,
      created_count: rows_count - existing, updated_count: existing, problems: problems.first(ProductImport::MAX_PROBLEMS), preview: preview)
  rescue CSV::MalformedCSVError => error
    @import.update!(status: :needs_fixing, problems: [ { "line" => nil, "messages" => [ "The file couldn't be read: #{error.message}" ] } ])
  end

  private
    # A product's unit can't change while a branch holds stock of it: 50 bags would become 50 pieces.
    def unit_changes(units_by_sku)
      return [] if units_by_sku.empty?

      stocked = @account.products.where(sku: units_by_sku.keys).joins(:stock_levels).where.not(stock_levels: { quantity: 0 }).distinct.pluck(:sku, :unit_id)
      changing = stocked.select { |sku, unit_id| units_by_sku[sku] != unit_id }.map(&:first).sort
      changing.any? ? [ { "line" => nil, "messages" => [ "Products with stock, whose unit can't change: #{changing.first(20).join(", ")}" ] } ] : []
    end

    # A barcode can only belong to one product: flag repeats in the file, and codes already used by a product with another SKU.
    def barcode_conflicts(barcodes)
      conflicts = []
      repeated = barcodes.select { |_, count| count > 1 }.keys
      conflicts << { "line" => nil, "messages" => [ "Barcodes used on more than one row: #{repeated.first(20).join(", ")}" ] } if repeated.any?

      codes_by_sku = @import.rows.filter_map { |data| [ data["barcode"].to_s.delete(" "), data["sku"].to_s.strip.upcase ] if data["barcode"].present? }.to_h
      taken = @account.products.joins(:barcodes).where(barcodes: { code: codes_by_sku.keys }).pluck("barcodes.code", :sku)
      clashes = taken.reject { |code, sku| codes_by_sku[code] == sku }
      conflicts << { "line" => nil, "messages" => [ "Barcodes already on other products: #{clashes.map(&:first).first(20).join(", ")}" ] } if clashes.any?
      conflicts
    end
end
