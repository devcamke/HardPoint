require "test_helper"

class StorefrontTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @account = accounts(:acme)
    Current.account = @account
    @store = @account.create_storefront!(enabled: true, collection_branch_ids: [ branches(:acme_main).id ])
    @items = {}
    @cart = Storefront::Cart.new(@store, @items)
  end

  def checkout(**attributes)
    Storefront::Checkout.new(storefront: @store, cart: @cart, name: "Grace Wanjiku", phone: "0711 222 333", **attributes)
  end

  test "the store sells active, priced products that aren't left out" do
    nails = products(:acme_nails)
    assert_includes @store.products, nails
    nails.update!(online: false)
    assert_not_includes @store.products, nails
  end

  test "stock shows per branch" do
    nails = products(:acme_nails)
    status, quantity = @store.availability(nails, branches(:acme_main))
    assert_equal nails.stock_at(branches(:acme_main)), quantity
    assert_includes %i[ in_stock low out ], status
  end

  test "a cart adds up, and refuses silly quantities" do
    assert_nil @cart.add(products(:acme_nails), 2)
    assert_nil @cart.add(products(:acme_nails), "1.5")
    assert_equal "3.5", @items[products(:acme_nails).id.to_s]
    assert_equal (products(:acme_nails).price_cents * 3.5).round, @cart.total_cents

    assert_match "Choose a quantity", @cart.set(products(:acme_nails), 0)
    assert_match "large orders", @cart.set(products(:acme_nails), 20_000)
  end

  test "checking out makes a confirmed online order for a new customer, and tells everyone" do
    @account.update!(sms_enabled: true)
    @cart.add(products(:acme_nails), 2)

    checkout_ = checkout(email: "grace@example.com", note: "Saturday morning")
    assert_enqueued_emails 2 do
      assert checkout_.place, checkout_.errors.full_messages.to_sentence
    end

    order = checkout_.order
    assert_equal [ "ordered", "online", branches(:acme_main) ], [ order.status, order.source, order.branch ]
    assert_equal [ "Grace Wanjiku", "254711222333" ], [ order.customer.name, order.customer.phone ]
    assert order.tracking_token.present?
    assert_match order.tracking_url, Sms::Message.last.body
    assert_equal "order_received", Sms::Message.last.purpose
    assert @cart.empty?
  end

  test "a returning customer is found by phone number" do
    customer = @account.customers.create!(name: "Grace W.", phone: "0711222333")
    @cart.add(products(:acme_nails), 1)
    checkout_ = checkout
    assert checkout_.place
    assert_equal customer, checkout_.order.customer
  end

  test "a number two customers share matches neither, so the order gets a customer of its own" do
    @account.customers.create!(name: "Grace W.", phone: "0711222333")
    @account.customers.create!(name: "Grace's son", phone: "0711222333")
    @cart.add(products(:acme_nails), 1)
    checkout_ = checkout
    assert checkout_.place
    assert_equal "Grace Wanjiku", checkout_.order.customer.name
  end

  test "checking out under someone's phone number never changes their record" do
    customer = @account.customers.create!(name: "Grace W.", phone: "0711222333")
    @cart.add(products(:acme_nails), 1)
    checkout_ = checkout(name: "Mallory", email: "mallory@evil.test")
    assert checkout_.place
    assert_nil customer.reload.email, "the email typed isn't put on their record"
    assert_equal "Grace W.", customer.name
    assert_match "Ordered online as Mallory, mallory@evil.test", checkout_.order.note
  end

  test "checking out needs a Kenyan mobile number, a collection branch and something in the cart" do
    assert_not checkout.place
    assert_match "cart is empty", checkout.tap(&:place).errors.full_messages.to_sentence

    @cart.add(products(:acme_nails), 1)
    bad = checkout(phone: "12345")
    assert_not bad.place
    assert bad.errors[:phone].any?

    elsewhere = checkout(branch_id: branches(:acme_yard).id)
    assert_not elsewhere.place
    assert elsewhere.errors[:branch_id].any?
  end

  test "bots that fill in the hidden field get nowhere" do
    @cart.add(products(:acme_nails), 1)
    assert_no_difference -> { CustomerOrder.count } do
      assert_not checkout(website: "http://spam.example").place
    end
  end

  test "the store won't promise stock that isn't there, or that earlier orders already hold" do
    assert_match "left to order", @cart.set(products(:acme_cement), 51)
    assert_nil @cart.set(products(:acme_cement), 40)

    held = @account.customer_orders.create!(branch: branches(:acme_main), customer: customers(:acme_contractor), status: :ordered,
      lines_attributes: [ { account: @account, product_code: "CEM-50", quantity: 30 } ])
    assert held.ordered?

    order = checkout(branch_id: branches(:acme_main).id)
    assert_not order.place
    assert_match "Only 20 Bamburi cement 50kg can be collected", order.errors.full_messages.to_sentence
  end

  test "the store charges what it showed: retail prices and shop-wide offers, never a customer's price list or a branch's offer" do
    contractor = customers(:acme_contractor) # on a price list: cement 760.00, not 800.00
    @account.promotions.create!(name: "Main only", kind: "percent_off", percent_off: 10, starts_on: Date.current, ends_on: Date.current + 7,
      product_ids: [ products(:acme_nails).id ], branch_ids: [ branches(:acme_main).id ])
    @account.promotions.create!(name: "Everywhere", kind: "percent_off", percent_off: 10, starts_on: Date.current, ends_on: Date.current + 7,
      product_ids: [ products(:acme_cement).id ])
    @cart.add(products(:acme_cement), 1)
    @cart.add(products(:acme_nails), 2)
    shown = @cart.total_cents
    assert_equal 720_00 + 2 * 250_00, shown, "ten percent off cement everywhere; the Main-only offer isn't shown"

    checkout_ = checkout(phone: contractor.phone)
    assert checkout_.place, checkout_.errors.full_messages.to_sentence
    order = checkout_.order
    assert_equal contractor, order.customer
    assert_equal shown, order.total_cents, "the order confirms at the total the customer saw at checkout"
    assert_equal [ 720_00, 250_00 ], order.lines.map(&:unit_price_cents)
    assert_equal [ "Everywhere", nil ], order.lines.map { _1.promotion&.name }
  end

  test "a locked shop doesn't take orders" do
    assert @store.taking_orders?
    @account.update!(subscription_status: "read_only")
    assert_not @store.reload.taking_orders?
  end

  test "a product's best branch is the one with most in stock" do
    @store.update!(collection_branch_ids: [ branches(:acme_main).id, branches(:acme_yard).id ])
    nails = products(:acme_nails)
    levels = { branches(:acme_main) => nails.stock_at(branches(:acme_main)), branches(:acme_yard) => nails.stock_at(branches(:acme_yard)) }
    _, _, branch = @store.best_availability(nails.reload)
    assert_equal levels.max_by { _2 }.first, branch
  end
end
