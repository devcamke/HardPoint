require "test_helper"

# Two requests acting on the same record at once: a double-tapped Pay button, an M-Pesa callback
# arriving as the cashier takes a card, two tills on one customer. Each request has its own copy
# of the record, loaded before the other committed; these tests hand the second request a stale
# copy, which is what it would have been holding, and check the locks make it see the truth.
class ConcurrencyTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:carl))
    @shift = shifts(:acme_front_open)
  end

  def open_sale(customer: nil)
    sale = @shift.current_sale
    sale.change_customer(customer) if customer
    sale.add(products(:acme_nails), quantity: 4) # 1,000.00
    sale
  end

  def locks_taken
    sql = []
    callback = ->(*, payload) { sql << payload[:sql] if payload[:sql].include?("FOR UPDATE") }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    sql
  end

  test "a second payment on a sale that has just been completed is refused, and nothing is sold twice" do
    sale = open_sale
    stale = Sale.find(sale.id)
    stock = products(:acme_nails).stock_at(@shift.branch)

    assert sale.pay(tender: "card", reference: "VISA 1").persisted?
    second = assert_raises(ArgumentError) { stale.pay(tender: "card", reference: "VISA 2") }
    assert_match "can't take payments", second.message

    assert_equal [ 1, 1000_00 ], [ sale.reload.payments.count, sale.paid_cents ]
    assert_equal stock - 4, products(:acme_nails).stock_at(@shift.branch), "stock taken once"
    assert_equal 1, products(:acme_nails).stock_movements.where(source: sale).count
  end

  test "account payments lock the customer, so two tills can't spend the same credit" do
    sale = open_sale(customer: customers(:acme_contractor))

    sql = locks_taken { sale.pay(tender: "on_account") }
    assert sql.any? { _1.match?(/FROM "sales".*FOR UPDATE/) }
    assert sql.any? { _1.match?(/FROM "customers".*FOR UPDATE/) }
  end

  test "a return holds the sale, so a second return (or a void) waits and counts what it took back" do
    sale = open_sale.tap { _1.pay(tender: "cash") }.reload
    returning = -> { accounts(:acme).sale_returns.create(sale: sale, shift: @shift, refund_method: "cash", approver: users(:amina),
      lines_attributes: [ { sale_line: sale.lines.sole, quantity: 4, restock: true } ]) }

    assert locks_taken { assert returning.call.persisted? }.any? { _1.match?(/FROM "sales".*FOR UPDATE/) }
    assert_match "can still be returned", returning.call.errors.full_messages.to_sentence
  end

  test "an order on one till can't be loaded on another, and a deposit can't be refunded twice" do
    order = accounts(:acme).customer_orders.create!(customer: customers(:acme_contractor), branch: @shift.branch,
      lines_attributes: [ { product: products(:acme_nails), quantity: 2, unit_price_cents: 250_00 } ])
    order.take_deposit(amount_cents: 100_00, tender: "cash", shift: @shift)

    assert order.load_into(@shift.current_sale), order.errors.full_messages.to_sentence
    @shift.current_sale.park
    second_sale = accounts(:acme).sales.create!(branch: @shift.branch, register: @shift.register, shift: @shift, cashier: users(:carl))
    assert_not CustomerOrder.find(order.id).load_into(second_sale)
    assert_match "already on", CustomerOrder.find(order.id).tap { _1.load_into(second_sale) }.errors.full_messages.to_sentence

    stale = CustomerOrder.find(order.id)
    assert order.refund_deposit(amount_cents: 100_00, tender: "cash", shift: @shift).persisted?
    assert_match "more than", stale.refund_deposit(amount_cents: 100_00, tender: "cash", shift: @shift).errors.full_messages.to_sentence
  end

  test "a webhook retry claims each delivery, so a run overlapping another sends it once" do
    endpoint = accounts(:acme).webhook_endpoints.create!(url: "https://hooks.example.com/hardpoint", event_types: %w[ sale.completed ])
    fake_transport(WebhookDelivery, "/hardpoint" => [ 500, {} ])
    delivery = endpoint.send_test
    delivery.deliver

    overlapping = 0
    fake_transport(WebhookDelivery, "/hardpoint" => ->(_) { overlapping += 1; WebhookDelivery.retry_due if overlapping == 1; {} })
    travel 2.minutes do
      WebhookDelivery.retry_due
    end
    assert_equal 1, overlapping, "the run that started while the first was sending found it claimed"
    assert delivery.reload.delivered?
  end
end
