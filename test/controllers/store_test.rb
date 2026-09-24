require "test_helper"

class StoreTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @account = accounts(:acme)
    Account.without_isolation { Current.set(account: @account) { @account.create_storefront!(enabled: true, headline: "Build it with Acme", collection_branch_ids: [ branches(:acme_main).id ]) } }
    use_account @account
    @nails = products(:acme_nails)
  end

  def add_to_cart(product = @nails, quantity = 2)
    post store_cart_items_path, params: { product_id: product.id, quantity: quantity }
  end

  test "a customer browses, adds to the cart, checks out and follows the order" do
    get store_root_path
    assert_response :success
    assert_select "h1", "Build it with Acme"
    assert_select "##{dom_id(@nails)}"

    get store_products_path(q: "nail")
    assert_select "##{dom_id(@nails)}"

    get store_product_path(@nails)
    assert_select "#availability", /Main/

    add_to_cart
    get store_cart_path
    assert_select "#cart_link .badge", "1"

    get new_store_checkout_path
    assert_response :success
    assert_enqueued_emails 1 do
      post store_checkout_path, params: { checkout: { name: "Grace Wanjiku", phone: "0711 222 333", branch_id: branches(:acme_main).id } }
    end
    token, reference = Account.without_isolation { @account.customer_orders.online.last.then { [ _1.tracking_token, _1.reference ] } }
    assert_redirected_to store_order_path(token)
    follow_redirect!
    assert_select "h1", "Order #{reference}"
    assert_select "#order_progress li.bg-green-600", 1

    get store_cart_path
    assert_select "#cart_link .badge", "0"
  end

  test "orders can only be followed with their token" do
    get store_order_path("not-a-token")
    assert_response :not_found
  end

  test "an order placed while a paybill exists shows how to pay ahead" do
    Account.without_isolation { Current.set(account: @account) { @account.mpesa_shortcodes.create!(name: "Paybill", shortcode: "174379", environment: "simulator") } }
    add_to_cart
    post store_checkout_path, params: { checkout: { name: "Grace", phone: "0711222333", branch_id: branches(:acme_main).id } }
    follow_redirect!
    assert_select "#pay_ahead", /174379/
  end

  test "products left out of the store, and other shops' products, can't be seen or bought" do
    Account.without_isolation { @nails.update!(online: false) }
    get store_product_path(@nails)
    assert_response :not_found
    add_to_cart
    assert_response :not_found

    get store_product_path(products(:bolt_hammer))
    assert_response :not_found
  end

  test "no store unless it's switched on" do
    Account.without_isolation { @account.storefront.update!(enabled: false) }
    get store_root_path
    assert_response :not_found
    assert_match "doesn't have an online store", response.body
  end

  test "a read-only shop can be browsed but takes no orders" do
    add_to_cart
    Account.without_isolation { @account.update!(subscription_status: "read_only") }
    get store_root_path
    assert_match "not taking orders online", response.body

    post store_checkout_path, params: { checkout: { name: "Grace", phone: "0711222333", branch_id: branches(:acme_main).id } }
    assert_redirected_to store_cart_path
    assert_equal 0, Account.without_isolation { @account.customer_orders.online.count }
  end

  test "staff see online orders marked, and the owner sets up the store" do
    add_to_cart
    post store_checkout_path, params: { checkout: { name: "Grace", phone: "0711222333", branch_id: branches(:acme_main).id } }

    sign_in_as users(:amina), account: @account
    get customer_orders_path
    assert_select ".badge", "Online"

    patch storefront_path, params: { storefront: { enabled: "1", headline: "New headline", collection_branch_ids: [ "", branches(:acme_yard).id ] } }
    assert_redirected_to edit_storefront_path
    assert_equal [ branches(:acme_yard).id ], Account.without_isolation { @account.storefront.reload.collection_branch_ids }
  end

  test "a product never stocked at a branch shows as out of stock, and quantities are in plain words" do
    fresh = Account.without_isolation { Current.set(account: @account) { @account.products.create!(name: "Tile cutter", sku: "TC-1", price_cents: 250000, unit: @account.default_unit) } }
    get store_product_path(fresh)
    assert_response :success
    assert_select "#availability", /Out of stock/

    Account.without_isolation { Current.set(account: @account) { @account.storefront.update!(show_stock_levels: true) } }
    get store_product_path(@nails)
    assert_select "#availability", /\d+ (kilograms|pieces|kgs?) in stock|Only \d+ .+ left|Out of stock/
  end
end
