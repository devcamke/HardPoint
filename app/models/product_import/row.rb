# One spreadsheet row, cleaned up and checked against the shop's catalogue.
class ProductImport::Row
  attr_reader :line, :attributes, :problems, :category_name, :brand_name, :barcode, :stock

  def initialize(line, data, lookups)
    @line, @data, @lookups = line, data, lookups
    @problems = []
    parse
  end

  def valid?
    problems.empty?
  end

  def sku
    attributes[:sku]
  end

  private
    def parse
      name = value(:name)
      problems << "name is missing" if name.blank?

      price = money(:price, required: true)
      cost = money(:cost)
      unit = lookup(:unit, @lookups.units) || @lookups.default_unit
      tax_rate = lookup(:tax_rate, @lookups.tax_rates)
      reorder_level = decimal(:reorder_level) || 0
      @stock = decimal(:stock)
      @category_name = value(:category).presence
      @brand_name = value(:brand).presence
      @barcode = value(:barcode).presence&.delete(" ")

      problems << "stock for #{unit.name.downcase} must be a whole number" if @stock && unit && !unit.valid_quantity?(@stock)
      problems << "stock can't be negative" if @stock&.negative?

      @attributes = { sku: value(:sku).presence&.upcase, name: name&.squish, price_cents: price, cost_cents: cost || 0,
                      unit_id: unit&.id, tax_rate_id: tax_rate&.id, reorder_level: reorder_level, active: active? }
    end

    def value(column)
      @data[column.to_s].to_s.strip
    end

    def money(column, required: false)
      raw = value(column)
      return problems.push("#{column} is missing") && nil if raw.blank? && required
      return if raw.blank?

      cents = Monetary.to_cents(raw)
      problems << "#{column} “#{raw}” isn't a number" if cents.nil?
      problems << "#{column} can't be negative" if cents&.negative?
      cents
    end

    def decimal(column)
      raw = value(column)
      return if raw.blank?

      BigDecimal(raw.delete(","), exception: false).tap { |number| problems << "#{column} “#{raw}” isn't a number" if number.nil? }
    end

    def lookup(column, table)
      raw = value(column)
      return if raw.blank?

      table[raw.downcase].tap { |record| problems << "#{column} “#{raw}” doesn't exist (add it in Settings first)" if record.nil? }
    end

    def active?
      !value(:active).downcase.in?(%w[ no n false 0 inactive ])
    end
end
