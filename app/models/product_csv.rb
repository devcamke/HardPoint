# The product spreadsheet format, shared by export and import so a shop can export, edit in
# Excel or Google Sheets, and import again.
class ProductCsv
  HEADERS = %w[ sku name barcode category brand unit price cost tax_rate reorder_level stock active ].freeze

  def initialize(products, branch:, include_costs: true)
    @products, @branch, @include_costs = products, branch, include_costs
  end

  def to_csv
    CSV.generate do |csv|
      csv << HEADERS
      @products.includes(:category, :brand, :unit, :tax_rate, :barcodes).in_batches(of: 1000) do |batch|
        stock = StockLevel.where(branch: @branch, product_id: batch.select(:id)).pluck(:product_id, :quantity).to_h
        batch.each { |product| csv << row_for(product, stock[product.id]) }
      end
    end
  end

  private
    def row_for(product, stock)
      [ product.sku, product.name, product.primary_barcode, product.category&.name, product.brand&.name, product.unit.name,
        format_money(product.price_cents), (format_money(product.cost_cents) if @include_costs), product.tax_rate&.name,
        format_quantity(product.reorder_level), (format_quantity(stock || 0) if product.track_stock?), product.active? ? "yes" : "no" ]
    end

    def format_money(cents)
      format("%.2f", cents / 100.0)
    end

    def format_quantity(amount)
      amount.to_d.to_s("F").delete_suffix(".0")
    end
end
