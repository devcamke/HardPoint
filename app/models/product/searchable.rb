module Product::Searchable
  extend ActiveSupport::Concern

  included do
    # Every word must appear in the name or SKU ("pvc 2 inch" finds "PVC pipe 2 inch 6m"), or the
    # whole query must be a barcode. Trigram indexes on name and sku keep this fast for big catalogues.
    scope :search, ->(query) do
      query = query.to_s.squish
      next all if query.blank?

      matching_words = query.split.first(8).inject(all) do |scope, word|
        scope.where("products.name ILIKE :word OR products.sku ILIKE :word", word: "%#{sanitize_sql_like(word)}%")
      end

      matching_words.or(where(id: Barcode.where(code: query).select(:product_id)))
        .order(Arel.sql(sanitize_sql_array([ "(products.sku = upper(?)) DESC, similarity(products.name, ?) DESC, products.name", query, query ])))
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
