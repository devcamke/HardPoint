# The back office is arranged as apps, the way Odoo does it: a home menu of app tiles, and
# a top bar showing the current app's name and its own menu.
module NavigationHelper
  App = Data.define(:key, :name, :path, :color, :icon, :menu, :prefixes) do
    def match_length(path)
      candidates = menu.map { _1[1] } + prefixes + [ self.path ]
      candidates.map { |prefix| path == prefix || path.start_with?("#{prefix}/") ? prefix.length : 0 }.max
    end
  end

  ICONS = {
    dashboard: "M3 13h8V3H3v10Zm0 8h8v-6H3v6Zm10 0h8V11h-8v10Zm0-18v6h8V3h-8Z",
    till: "M4 4h16v10H4zM2 18h20v2H2zM7 7h10M7 10h6",
    sales: "M3 3h2l2.4 12.2a1 1 0 0 0 1 .8h9.2a1 1 0 0 0 1-.8L21 7H6M9 20a1 1 0 1 0 0 .01M18 20a1 1 0 1 0 0 .01",
    hire: "M14.7 6.3a4 4 0 0 0-5.4 5.4L3 18v3h3l6.3-6.3a4 4 0 0 0 5.4-5.4l-2.6 2.6-2.4-.6-.6-2.4Z",
    products: "M21 8 12 3 3 8v8l9 5 9-5V8ZM3 8l9 5 9-5M12 13v8",
    stock: "M3 21V9l9-6 9 6v12M7 21v-8h10v8M7 17h10",
    purchasing: "M6 2h9l5 5v15H6zM14 2v6h6M9 13h8M9 17h8",
    reports: "M4 20V10M10 20V4M16 20v-7M22 20H2",
    staff: "M16 11a4 4 0 1 0-8 0 4 4 0 0 0 8 0ZM4 21a8 8 0 0 1 16 0",
    settings: "M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6Zm7.4-3a7.4 7.4 0 0 0-.1-1.3l2-1.6-2-3.4-2.4 1a7.3 7.3 0 0 0-2.2-1.3L14.4 3h-4l-.4 2.5a7.3 7.3 0 0 0-2.2 1.3l-2.4-1-2 3.4 2 1.6a7.4 7.4 0 0 0 0 2.6l-2 1.6 2 3.4 2.4-1a7.3 7.3 0 0 0 2.2 1.3l.4 2.5h4l.4-2.5a7.3 7.3 0 0 0 2.2-1.3l2.4 1 2-3.4-2-1.6c.1-.4.1-.9.1-1.3Z",
    help: "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20ZM9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3M12 17h.01"
  }.freeze

  def navigation_apps
    @navigation_apps ||= begin
      m = current_membership
      apps = [ App.new(:dashboard, "Dashboard", root_path, "#5b8def", :dashboard, [], []) ]
      apps << App.new(:till, "Point of Sale", pos_path, "#e46f2f", :till, [], []) if m&.can_sell?

      if m&.can_sell? || m&.can_manage_receivables?
        menu = []
        menu += [ [ "Sales", sales_path ], [ "Orders & quotes", customer_orders_path ], [ "Deliveries", delivery_notes_path ],
                  [ "Returns", returns_path ], [ "Shifts", shifts_path ] ] if m.can_sell?
        menu += [ [ "Customers", customers_path ], [ "Jobs", jobs_path ] ]
        menu << [ "Who owes us", receivables_path ] if m.can_manage_receivables?
        apps << App.new(:sales, "Sales", menu.first[1], "#d9534f", :sales, menu, [])
      end

      if m&.can_sell? && Current.account.hire_items.exists? || m&.can_manage_catalogue?
        apps << App.new(:hire, "Tool Hire", hire_agreements_path, "#f0ad4e", :hire,
          [ [ "Agreements", hire_agreements_path ], [ "Tools", hire_items_path ] ], [])
      end

      apps << App.new(:products, "Products", products_path, "#00a09d", :products,
        [ [ "Products", products_path ], [ "Promotions", promotions_path ], [ "Price lists", price_lists_path ],
          [ "Categories", categories_path ], [ "Brands", brands_path ], [ "Units", units_path ], [ "Tax rates", tax_rates_path ] ],
        [ "/labels", "/product_imports" ])

      apps << App.new(:stock, "Inventory", stock_path, "#26a69a", :stock,
        [ [ "Overview", stock_path ], [ "Transfers", stock_transfers_path ], [ "Stock takes", stock_counts_path ],
          [ "Reorder list", reorder_list_path ], [ "Expiry", stock_batches_path ], [ "Movements", stock_movements_path ] ],
        [ "/stock_adjustments" ])

      if m&.can_purchase? || m&.can_manage_payables?
        menu = []
        menu += [ [ "Orders", purchase_orders_path ], [ "Receiving", goods_receipts_path ], [ "Returns", supplier_returns_path ],
                  [ "Reorder suggestions", reorder_suggestions_path ] ] if m.can_purchase?
        menu << [ "Suppliers", suppliers_path ]
        menu += [ [ "Invoices", supplier_invoices_path ], [ "What we owe", payables_path ] ] if m.can_manage_payables?
        apps << App.new(:purchasing, "Purchase", menu.first[1], "#8e6bbf", :purchasing, menu, [])
      end

      apps << App.new(:reports, "Reports", reports_path, "#3f7fbf", :reports, [], []) if m&.can_view_reports?

      if m&.can_manage_staff?
        apps << App.new(:staff, "Employees", memberships_path, "#c2569b", :staff,
          [ [ "Staff", memberships_path ], [ "Activity", events_path ] ], [])
      end

      apps << App.new(:settings, "Settings", settings_path, "#6c757d", :settings,
        [ [ "General", settings_path ], [ "Branches", branches_path ], [ "Tills", registers_path ] ],
        %w[ /account /account_data /account_exports /billing /onboarding /storefront /developers /api_keys /webhook_endpoints
            /mpesa /etims /texts /currencies /loyalty ])
      apps << App.new(:help, "Help", help_path, "#4d9f6f", :help, [], [ "/support_requests" ])
      apps
    end
  end

  def current_app
    @current_app ||= navigation_apps
      .map { [ _1, _1.match_length(request.path) ] }
      .select { _2.positive? }
      .max_by { _2 }&.first
  end

  def app_icon(app, css: "size-6")
    tag.svg(viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", stroke_width: 1.8, stroke_linecap: "round",
      stroke_linejoin: "round", class: css, aria: { hidden: true }) { tag.path(d: ICONS.fetch(app.icon)) }
  end

  def app_menu_item_active?(path)
    request.path == path || request.path.start_with?("#{path}/")
  end
end
