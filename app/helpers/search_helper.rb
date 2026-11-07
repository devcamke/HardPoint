module SearchHelper
  Result = Data.define(:label, :detail, :path)

  # [ [ heading, [ Result… ] ] ], best guesses first, limited to what this person can open.
  def search_groups(query, limit: 6)
    m = current_membership
    groups = []

    products = Current.account.products.active.search(query).includes(:unit).limit(limit).to_a
    if products.any?
      stock = StockLevel.where(branch: selected_branch, product_id: products.map(&:id)).pluck(:product_id, :quantity).to_h
      groups << [ "Products", products.map { |product|
        Result.new(product.name, "#{money(product.price_cents)} · #{quantity(stock.fetch(product.id, 0), product.unit)} at #{selected_branch&.name}", product_path(product))
      } ]
    end

    if m.can_sell? || m.can_manage_receivables?
      customers = Current.account.customers.search(query).alphabetically.limit(limit)
      groups << [ "Customers", customers.map { Result.new(_1.name, _1.phone, customer_path(_1)) } ] if customers.any?
    end

    if m.can_purchase? || m.can_manage_payables?
      suppliers = Current.account.suppliers.search(query).order(:name).limit(limit)
      groups << [ "Suppliers", suppliers.map { Result.new(_1.name, "Supplier", supplier_path(_1)) } ] if suppliers.any?
    end

    if (documents = search_documents(query)).any?
      groups << [ "Documents", documents ]
    end

    if (pages = search_pages(query).first(limit)).any?
      groups << [ "Pages", pages ]
    end

    if (product = products.first) && (actions = product_actions(product)).any?
      groups << [ "Do something with #{product.name}", actions ]
    end

    groups
  end

  private
    # A receipt, order or purchase order number typed or scanned in full: MAI-000123, MAI-O00012, MAI-PO00007.
    def search_documents(query)
      m = current_membership
      [
        (m.can_sell? && (sale = Current.account.sales.find_by_receipt_number(query)) && Result.new("Sale #{sale.receipt_number}", sale.status.humanize, sale_path(sale))),
        (m.can_sell? && (order = Current.account.customer_orders.find_by_reference(query)) && Result.new(order.reference, order.kind.to_s.humanize, customer_order_path(order))),
        (m.can_purchase? && (po = find_purchase_order(query)) && Result.new(po.reference, "Purchase order · #{po.status.humanize.downcase}", purchase_order_path(po)))
      ].select(&:itself)
    end

    def find_purchase_order(query)
      code, number = query.upcase.split("-PO", 2)
      Current.account.purchase_orders.joins(:branch).find_by(branches: { code: code }, number: number.to_i) if number.to_i.positive?
    end

    # Pages match on their name, the area they're in, and the names people may remember them by.
    def search_pages(query)
      words = query.downcase.split
      searchable_pages.select { |page, keywords| words.all? { "#{page.label} #{page.detail} #{keywords}".downcase.include?(_1) } }.map(&:first)
    end

    def searchable_pages
      m = current_membership
      pages = [ *navigation_apps, settings_app ].flat_map do |app|
        (app.menu.presence || [ [ app.name, app.path ] ]).map { |name, path| [ Result.new(name, app.name, path), "" ] }
      end
      pages += [
        [ Result.new("Reorder", "Stock", reorder_list_path), "reorder list reorder suggestions low stock inventory" ],
        [ Result.new("Stock movements", "Stock", stock_movements_path), "movements history inventory" ],
        [ Result.new("Barcode labels", "Stock", new_labels_path), "print labels" ],
        [ Result.new("Import products", "Stock", product_imports_path), "spreadsheet csv upload" ],
        [ Result.new("Help", "Guides", help_path), "how do i support" ]
      ]
      pages += [ [ Result.new("Returns to suppliers", "Buy", supplier_returns_path), "supplier returns debit notes purchase" ] ] if m.can_purchase?
      pages += [ [ Result.new("Supplier invoices", "Buy", supplier_invoices_path), "invoices bills purchase" ] ] if m.can_manage_payables?
      pages += [ [ Result.new("Features", "Settings", features_path), "switch on off tool hire jobs batches loyalty online store" ] ] if m.can_manage_account?
      pages += %w[ Categories Brands Units ].map { [ Result.new(_1, "Settings › Catalogue", public_send("#{_1.downcase}_path")), "products catalogue" ] }
      pages += [ [ Result.new("Tax rates", "Settings › Catalogue", tax_rates_path), "vat products" ],
                 [ Result.new("Price lists", "Settings › Catalogue", price_lists_path), "contractor wholesale prices" ] ]
      pages += [ [ Result.new("Staff", "Settings", memberships_path), "employees people pins" ] ] if m.can_manage_staff?
      # A page listed twice (in a menu, and here with the names people remember) keeps both sets of words.
      pages.group_by { _1.first.path }.map { |_, same| [ same.first.first, same.map(&:last).join(" ") ] }
    end

    def product_actions(product)
      m = current_membership
      supplier = product.preferred_supplier_product&.supplier
      [
        (Result.new("Order more", supplier ? "Draft a purchase order to #{supplier.name}" : "Draft a purchase order", new_purchase_order_path(supplier_id: supplier&.id)) if m.can_purchase?),
        (Result.new("Adjust stock", "Breakages, stock found, corrections", new_stock_adjustment_path(product_id: product.id)) if m.can_manage_stock? && product.track_stock?),
        (Result.new("Print labels", "Shelf labels with the barcode", new_labels_path(product_ids: [ product.id ])) if m.can_manage_catalogue?)
      ].compact
    end
end
