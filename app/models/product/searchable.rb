module Product::Searchable
  extend ActiveSupport::Concern

  included do
    # Every word must start a word of the name or SKU ("pvc 2 inch" finds "PVC pipe 2 inch 6m"; "CEM-5" finds
    # CEM-50), or the whole query must be a barcode. Words are looked up in search_terms, which stays fast under
    # row-level security. Only when that finds nothing does it look for the words anywhere ("ment" finds cement),
    # which reads the whole catalogue.
    scope :search, ->(query) do
      query = query.to_s.squish
      next all if query.blank?

      words = query.split.first(8)
      barcodes = Barcode.where(code: query)
      barcodes = barcodes.where(account_id: Current.account.id) if Current.account
      barcodes = barcodes.select(:product_id)

      # One set of ids (products with every word, and the barcode's), so Postgres looks each up rather than
      # reading the catalogue to test them.
      matching = where(arel_table[:id].in(Arel::Nodes::Union.new(SearchTerm.with_every_word("products", words), barcodes.arel)))
      unless matching.exists?
        matching = words.inject(all) do |scope, word|
          scope.where("products.name ILIKE :word OR products.sku ILIKE :word", word: "%#{sanitize_sql_like(word)}%")
        end.or(where(id: barcodes))
      end

      matching
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
