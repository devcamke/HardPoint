# Stock that isn't selling: products on hand that haven't sold (on their own or in a kit) for a
# number of days, or ever, with the money tied up in them.
class Report::DeadStock < Report
  self.title = "Dead stock"
  self.description = "Products in stock that haven't sold for a while, and the money tied up in them"
  self.group = "Stock"
  self.uses_period = false

  LIMIT = 500

  def self.options
    [ [ :days, "Not sold for", [ [ "30 days", "30" ], [ "60 days", "60" ], [ "90 days", "90" ], [ "180 days", "180" ], [ "a year", "365" ] ], "90" ] ]
  end

  def subtitle
    "Not sold for #{days} days · #{branch&.name || "All branches"}"
  end

  def days
    options[:days].to_i.clamp(1, 3650)
  end

  def sections
    rows = products.map do |product|
      last_sold = product.last_sold_at&.in_time_zone&.to_date
      [ Link.new("#{product.name} (#{product.sku})", product), product.category&.name, product.on_hand.to_d, product.unit.abbreviation,
        product.value_cents.to_i, last_sold || "Never", last_sold ? (Date.current - last_sold).to_i : nil ]
    end

    [ Section.new(columns: columns, rows: rows, totals: [ "Total", nil, nil, nil, rows.sum { _1[4] }, nil, nil ],
        note: "Sales through kits count as sales of their parts. At most #{LIMIT} products are listed, the most money first.") ]
  end

  private
    def columns
      [ Column.new("Product", :link), Column.new("Category", :text), Column.new("On hand", :quantity), Column.new("Unit", :text),
        Column.new("Value at cost", :money), Column.new("Last sold", :date), Column.new("Days", :count) ]
    end

    def products
      level_scope = branch ? "AND stock_levels.branch_id = #{branch.id.to_i}" : ""
      movement_scope = branch ? "AND stock_movements.branch_id = #{branch.id.to_i}" : ""

      account.products.where(track_stock: true).includes(:category, :unit)
        .joins("JOIN (SELECT product_id, SUM(quantity) AS on_hand FROM stock_levels WHERE quantity > 0 #{level_scope} GROUP BY product_id) held ON held.product_id = products.id")
        .joins("LEFT JOIN (SELECT product_id, MAX(created_at) AS last_sold_at FROM stock_movements WHERE reason = 'sold' #{movement_scope} GROUP BY product_id) sold ON sold.product_id = products.id")
        .where("sold.last_sold_at IS NULL OR sold.last_sold_at < ?", days.days.ago)
        .select("products.*, held.on_hand, sold.last_sold_at, ROUND(held.on_hand * products.cost_cents) AS value_cents")
        .order("value_cents DESC").limit(LIMIT)
    end
end
