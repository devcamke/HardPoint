require "test_helper"

# Walks every shop route that takes a record id and asks for another shop's record, signed in
# as an owner (who can reach everything in their own shop). Each must be refused or not found.
class TenantIsolationSweepTest < ActionDispatch::IntegrationTest
  # Route segments that aren't record ids.
  NOT_RECORDS = %w[ reports#show help#show ].freeze
  # Controllers whose :id names a record of another model.
  MODEL_FOR_CONTROLLER = {
    "etims_devices" => "Etims::Device", "etims_submissions" => "Etims::Submission", "mpesa_shortcodes" => "Mpesa::Shortcode",
    "pos/lines" => "SaleLine", "pos/mpesa_requests" => "Mpesa::StkRequest", "billings/mpesa_payments" => "Billing::Payment",
    "billings/invoices" => "Billing::Invoice", "customer_orders" => "CustomerOrder", "delivery_notes" => "DeliveryNote",
    "orders" => "CustomerOrder", "products/prices" => "PriceListItem", "products/components" => "KitComponent",
    "stock_counts/lines" => "StockCountLine", "deliveries" => "DeliveryNote", "returns" => "SaleReturn", "sale_returns" => "SaleReturn"
  }.freeze
  MODEL_FOR_PARAM = { "mpesa_shortcode_id" => "Mpesa::Shortcode", "etims_device_id" => "Etims::Device", "etims_submission_id" => "Etims::Submission",
    "delivery_id" => "WebhookDelivery" }.freeze

  setup { build_victim_records }

  def self.member_routes
    Rails.application.routes.routes.filter_map do |route|
      path = route.path.spec.to_s.delete_suffix("(.:format)")
      controller, action = route.defaults.values_at(:controller, :action)
      next unless controller && path.match?(/:\w*id\b/)
      next if controller.start_with?("admin/", "webhooks/", "rails/", "active_storage/", "action_mailbox/", "turbo/", "api/")
      next if NOT_RECORDS.include?("#{controller}##{action}")
      [ route.verb, path, controller, action ]
    end.uniq
  end

  def model_for(param, controller)
    name = if param == "id"
      MODEL_FOR_CONTROLLER[controller] || MODEL_FOR_CONTROLLER[controller.split("/").last] || controller.split("/").last.classify
    else
      MODEL_FOR_PARAM[param] || param.delete_suffix("_id").classify
    end
    name.safe_constantize
  end

  test "no shop can reach another shop's records through any route" do
    victim = accounts(:acme)
    sign_in_as users(:bob), account: accounts(:bolt)
    post pos_till_path, params: { register_id: registers(:bolt_front).id }
    post shifts_path, params: { shift: { opening_float: "1000" } }

    checked, skipped, leaks = 0, [], []
    self.class.member_routes.each do |verb, spec, controller, action|
      path = spec.gsub(/:(\w+)/) do
        param = Regexp.last_match(1)
        model = model_for(param, controller)
        record = model && Account.without_isolation { model.where(account_id: victim.id).first }
        record&.to_param || (skipped << "#{verb} #{spec} (no #{model || param})" and break)
      end
      next unless path.is_a?(String) && !path.include?(":")

      send verb.downcase.to_sym, path
      checked += 1
      leaks << "#{verb} #{path} → #{response.status} (#{controller}##{action})" unless response.status.in?([ 400, 403, 404, 422 ])
    end

    puts "\nTenant sweep: #{checked} routes checked, #{skipped.size} skipped\n  #{skipped.join("\n  ")}" if ENV["SWEEP_VERBOSE"]
    assert leaks.empty?, "Another shop's records were reachable:\n#{leaks.join("\n")}"
    assert_empty skipped, "Routes the sweep couldn't check (no record to aim at)"
  end

  test "no API key can reach another shop's records" do
    host! "api.localhost"
    key = Account.without_isolation { Current.set(account: accounts(:bolt)) { accounts(:bolt).api_keys.create!(name: "Sweep", scope: "write") } }
    victims = { "products" => Product, "customers" => Customer, "jobs" => Job, "sales" => Sale, "orders" => CustomerOrder, "order" => CustomerOrder }
    routes = Rails.application.routes.routes.filter_map do |route|
      path = route.path.spec.to_s.delete_suffix("(.:format)")
      [ route.verb, path ] if route.defaults[:controller].to_s.start_with?("api/") && path.include?(":")
    end.uniq

    checked = routes.map do |verb, spec|
      path = spec.gsub(/:(\w+)/) do
        model = victims.fetch(Regexp.last_match(1) == "id" ? spec.split("/")[2] : Regexp.last_match(1).delete_suffix("_id"))
        Account.without_isolation { model.where(account_id: accounts(:acme).id).where.not(model == Sale ? { status: "open" } : {}).first!.id }
      end
      send verb.downcase.to_sym, path, params: {}.to_json, headers: { "Authorization" => "Bearer #{key.token}", "Content-Type" => "application/json" }
      assert_response :not_found, "#{verb} #{path} answered #{response.status}"
      path
    end
    assert_operator checked.size, :>=, 8
  end

  private
    # One of everything in the victim shop, so every route has something to aim at.
    def build_victim_records
      acme = accounts(:acme)
      Account.without_isolation do
        Current.set(account: acme, session: acme.sessions.create!(user: users(:amina))) do
          shift = shifts(:acme_front_open)
          shortcode = acme.mpesa_shortcodes.create!(name: "Paybill", shortcode: "174379", environment: "simulator")
          acme.etims_devices.create!(branch: branches(:acme_main), environment: "simulator", tin: "P051234567X", serial_number: "SWEEP-1").initialize_with_kra

          sale = shift.current_sale
          sale.change_customer(customers(:acme_contractor))
          sale.update!(job: acme.jobs.create!(customer: customers(:acme_contractor), name: "Sweep job", budget: "100000"))
          sale.add(products(:acme_nails), quantity: 4)
          sale.pay(tender: "on_account", credit_approver: users(:amina))
          sale.reload
          acme.sale_returns.create!(sale: sale, shift: shift, refund_method: "cash", approver: users(:amina),
            lines_attributes: [ { sale_line: sale.lines.first, quantity: 1, restock: true } ])
          acme.delivery_notes.create!(sale: sale, address: "Plot 12, Mombasa Road")

          open_sale = shift.current_sale
          open_sale.add(products(:acme_nails), quantity: 1)
          open_sale.stk_requests.create!(account: acme, shortcode: shortcode, phone: "254722000111", amount_cents: 250_00, checkout_request_id: "ws_CO_SWEEP")

          acme.customer_orders.create!(branch: branches(:acme_main), customer: customers(:acme_contractor),
            lines_attributes: [ { account: acme, product_code: "NAIL-3", quantity: 10 } ])
          po = acme.purchase_orders.create!(supplier: suppliers(:acme_cement_distributor), branch: branches(:acme_main),
            lines_attributes: [ { product_code: "CEM-50", quantity: 10 } ])
          po.mark_sent
          acme.goods_receipts.create!(supplier: po.supplier, branch: po.branch, purchase_order: po,
            lines_attributes: [ { purchase_order_line_id: po.lines.sole.id, quantity: 10 } ])
          suppliers(:acme_cement_distributor).supplier_invoices.create!(account: acme, number: "SWEEP-1", invoice_date: Date.current, total: "1000")
          acme.stock_counts.create!(branch: branches(:acme_main), category: categories(:acme_building))
          acme.stock_transfers.create!(from_branch: branches(:acme_main), to_branch: branches(:acme_yard), lines_attributes: [ { product_code: "CEM-50", quantity: 1 } ])
          acme.product_imports.create!(csv: "sku,name,price\nSW-1,Sweep,1\n", branch: branches(:acme_main), filename: "sweep.csv")

          acme.account_exports.create!
          products(:acme_pipe).update!(tracks_batches: true)
          products(:acme_pipe).move_stock(branch: branches(:acme_main), quantity: 5, reason: "received", batch: { number: "SWEEP-1", expires_on: 1.month.from_now.to_date })
          tool = acme.hire_items.create!(branch: branches(:acme_main), name: "Mixer", asset_tag: "SWEEP-MIX", daily_rate: "1500")
          HireAgreement.hire_out(branch: branches(:acme_main), customer: customers(:acme_contractor), items: [ tool ], due_back_at: 2.days.from_now)
          acme.api_keys.create!(name: "Victim key")
          endpoint = acme.webhook_endpoints.create!(url: "https://hooks.example.com/victim", event_types: %w[ sale.completed ])
          endpoint.deliveries.create!(account: acme, event: "ping", event_id: SecureRandom.uuid, payload: {}, status: "failed", attempts: 7)

          invoice = acme.start_subscription_now
          invoice.payments.create!(account: acme, provider: "mpesa", amount_cents: invoice.amount_cents, reference: "ws_CO_SWEEP_BILL")
        end
      end
    end
end
