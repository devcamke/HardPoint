module Product::Searchable
  extend ActiveSupport::Concern

  included do
    # Every word must appear in the name or SKU ("pvc 2 inch" finds "PVC pipe 2 inch 6m"), or the
    # whole query must be a barcode. The matching runs in search_product_ids (SearchFunctions), which
    # row-level security doesn't apply to, so the trigram indexes on name and sku keep this fast for big
    # catalogues; outside a shop (nothing current) it falls back to plain conditions.
    scope :search, ->(query) do
      query = query.to_s.squish
      next all if query.blank?

      patterns = query.split.first(8).map { "%#{sanitize_sql_like(_1)}%" }
      matching = if (shop = Current.account&.id)
        where("products.id IN (SELECT search_product_ids(?, ARRAY[?]::text[], ?))", shop, patterns, query)
      else
        patterns.inject(all) { |scope, pattern| scope.where("products.name ILIKE :word OR products.sku ILIKE :word", word: pattern) }
          .or(where(id: Barcode.where(code: query).select(:product_id)))
      end

      matching.order(Arel.sql(sanitize_sql_array([ "(products.sku = upper(?)) DESC, similarity(products.name, ?) DESC, products.name", query, query ])))
    end
  end

  class_methods do
    # For scanners and typed codes: an exact barcode or SKU.
    def find_by_code(code)
      code = code.to_s.strip
      return if code.blank?

      joins(:barcodes).find_by(barcodes: { code: code }) || find_by(sku: code.upcase)
    end
  end
end
