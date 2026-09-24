require "test_helper"
require_relative "api_test_case"

class Api::V1Test < ApiTestCase
  setup do
    @acme = accounts(:acme)
    @key = api_key_for(@acme)
  end

  test "keys: none, wrong, revoked, and the plan" do
    get api_v1_shop_path
    assert_response :unauthorized
    assert_equal "unauthorized", error_code

    get api_v1_shop_path, headers: { "Authorization" => "Bearer hp_#{"x" * 40}" }
    assert_response :unauthorized

    api_get api_v1_shop_path
    assert_response :success
    assert_equal [ "Acme Hardware", "KES" ], json.values_at("name", "currency")
    api_get api_v1_products_path, limit: 1
    assert json["data"].first["updated_at"].end_with?("Z"), "times are UTC"
    assert Account.without_isolation { @key.reload.last_used_at }

    Account.without_isolation { @acme.update!(plan: "starter") }
    api_get api_v1_shop_path
    assert_response :forbidden
    assert_equal "plan", error_code

    Account.without_isolation { @acme.update!(plan: "business"); Current.set(account: @acme) { @key.revoke } }
    api_get api_v1_shop_path
    assert_response :unauthorized
  end

  test "a key only ever sees its own shop" do
    bolt_product = products(:bolt_hammer)
    api_get api_v1_product_path(bolt_product)
    assert_response :not_found

    api_get api_v1_products_path
    assert_not_includes json["data"].map { _1["id"] }, bolt_product.id
    assert_equal Account.without_isolation { @acme.products.count }, json["data"].size
  end

  test "products page by cursor and filter by time" do
    api_get api_v1_products_path, limit: 2
    first_page = json["data"].map { _1["id"] }
    assert_equal 2, first_page.size
    assert json["next_cursor"]
    assert_match 'rel="next"', response.headers["Link"]

    api_get api_v1_products_path, limit: 2, after: json["next_cursor"]
    assert_empty first_page & json["data"].map { _1["id"] }

    nails = products(:acme_nails)
    Account.without_isolation { nails.update_columns(updated_at: 1.minute.from_now) }
    api_get api_v1_products_path, updated_since: 30.seconds.from_now.iso8601
    assert_equal [ nails.id ], json["data"].map { _1["id"] }

    api_get api_v1_products_path, updated_since: "yesterday"
    assert_response :bad_request
  end

  test "a product is created with a barcode and changed" do
    api_post api_v1_products_path, { product: { sku: "api-1", name: "Wheelbarrow", price_cents: 450000, category: "Garden", unit: "Piece", tax_rate: "16", barcodes: [ "6009876543210" ] } }
    assert_response :created
    assert_equal [ "API-1", 450000, "Garden", "16.0", [ "6009876543210" ] ], json.values_at("sku", "price_cents", "category", "tax_rate", "barcodes")

    api_patch api_v1_product_path(json["id"]), { product: { price_cents: 470000, active: false } }
    assert_response :success
    assert_equal [ 470000, false ], json.values_at("price_cents", "active")

    event = Account.without_isolation { Event.where(account: @acme, eventable_type: "Product").order(:id).last }
    assert_equal "Test key", event.particulars["api_key"]
  end

  test "invalid input is explained" do
    api_post api_v1_products_path, { product: { name: "" } }
    assert_response :unprocessable_entity
    assert_equal "invalid", error_code
    assert json.dig("error", "details", "name")

    api_post api_v1_products_path, { name: "no wrapper" }
    assert_response :bad_request
  end

  test "read keys can't write, and a read-only shop can't be changed" do
    reader = api_key_for(@acme, scope: "read")
    api_post api_v1_customers_path, { customer: { name: "Kamau" } }, key: reader
    assert_response :forbidden
    assert_equal "read_only_key", error_code

    Account.without_isolation { @acme.update!(subscription_status: "read_only") }
    api_post api_v1_customers_path, { customer: { name: "Kamau" } }
    assert_response :payment_required
    api_get api_v1_customers_path
    assert_response :success
  end

  test "a web shop's click-and-collect order, sent twice with the same idempotency key" do
    body = { order: { branch_id: branches(:acme_main).id, note: "Collect Saturday",
      customer: { name: "Grace Wanjiku", phone: "0711 222 333" }, lines: [ { sku: "NAIL-3", quantity: "2" } ] } }

    assert_difference -> { Account.without_isolation { @acme.customer_orders.count } }, 1 do
      api_post api_v1_orders_path, body, "Idempotency-Key" => "cart-42"
      assert_response :created
      api_post api_v1_orders_path, body, "Idempotency-Key" => "cart-42"
      assert_response :created
    end
    order = json
    assert_equal [ "ordered", "Grace Wanjiku", "2.0" ], [ order["status"], order["customer_name"], order["lines"].sole["quantity"] ]

    api_post api_v1_orders_path, body.deep_merge(order: { note: "different" }), "Idempotency-Key" => "cart-42"
    assert_equal "idempotency_key_reused", error_code

    api_post api_v1_order_cancellation_path(order["id"]), {}
    assert_equal "cancelled", json["status"]
  end

  test "an order for something the shop doesn't sell is refused" do
    api_post api_v1_orders_path, { order: { customer: { name: "X", phone: "0700000001" }, lines: [ { sku: "NOPE", quantity: 1 } ] } }
    assert_response :unprocessable_entity
    assert_match "NOPE", json.dig("error", "message")
  end

  test "sales and stock levels read" do
    sale = Account.without_isolation do
      Current.set(account: @acme, session: @acme.sessions.create!(user: users(:carl))) do
        shifts(:acme_front_open).current_sale.tap { _1.add(products(:acme_nails), quantity: 2); _1.pay(tender: "cash") }
      end
    end

    api_get api_v1_sale_path(sale)
    assert_equal [ "completed", 1 ], [ json["status"], json["lines"].size ]
    assert_equal "cash", json["payments"].sole["tender"]

    api_get api_v1_stock_levels_path, product_id: products(:acme_nails).id
    assert json["data"].all? { _1["sku"] == products(:acme_nails).sku }
  end
end
