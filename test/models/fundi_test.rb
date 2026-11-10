require "test_helper"

class FundiTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:amina))
    @shift = shifts(:acme_front_open)
    @fundi = fundis(:acme_mason)
    accounts(:acme).update!(fundi_commission_percent: 2)
    stock_up products(:acme_nails), 100
  end

  def sell(product, quantity:, fundi: @fundi)
    sale = @shift.current_sale
    sale.change_fundi(fundi)
    assert sale.add(product, quantity: quantity).persisted?
    payment = sale.pay(tender: "cash", tendered_cents: sale.total_cents)
    assert payment.persisted?, payment.errors.full_messages.to_sentence
    sale
  end

  def net(sale) = sale.total_cents - sale.tax_cents

  test "a completed sale earns the fundi the shop's rate on its value before tax, and nothing before it's paid" do
    sale = @shift.current_sale
    sale.change_fundi(@fundi)
    sale.add(products(:acme_nails), quantity: 4) # 1,000.00 with tax
    assert_equal 0, @fundi.balance_cents, "nothing is earned on an open sale"

    sale.pay(tender: "cash")
    entry = @fundi.entries.sole
    assert_equal [ "earned", (net(sale) * 0.02).round, net(sale) ], [ entry.kind, entry.amount_cents, entry.sales_cents ]
    assert_equal sale, entry.source
  end

  test "a category's rate beats the shop's, a parent category's covers its children, and a fundi's own rate beats both" do
    categories(:acme_fasteners).update!(fundi_commission_percent: 5)
    sale = sell(products(:acme_nails), quantity: 4)
    assert_equal (net(sale) * 0.05).round, @fundi.balance_cents

    pipes = accounts(:acme).categories.create!(name: "Pipes", parent: categories(:acme_plumbing))
    categories(:acme_plumbing).update!(fundi_commission_percent: 3)
    products(:acme_pipe).update!(category: pipes)
    assert_equal 3, @fundi.commission_percent_for(products(:acme_pipe))

    @fundi.update!(commission_percent: 10)
    assert_equal 10, @fundi.commission_percent_for(products(:acme_pipe))
    assert_equal 10, @fundi.commission_percent_for(products(:acme_nails))
  end

  test "a void takes the commission back, and a return takes back its share" do
    sale = sell(products(:acme_nails), quantity: 4)
    earned = @fundi.balance_cents

    sale_return = sale.sale_returns.create!(account: accounts(:acme), branch: sale.branch, shift: @shift, refund_method: "cash",
      lines_attributes: [ { sale_line_id: sale.lines.sole.id, quantity: 1, restock: true } ])
    taken = @fundi.entries.find_by!(source: sale_return)
    assert_equal "reversed", taken.kind
    assert_in_delta(-earned / 4.0, taken.amount_cents, 1)

    other = sell(products(:acme_nails), quantity: 2)
    before = @fundi.reload.balance_cents
    assert other.void(reason: "Wrong customer", by: users(:amina))
    assert_equal before - (net(other) * 0.02).round, @fundi.reload.balance_cents
  end

  test "a sale without a fundi, or worth nothing at the rate, earns nothing" do
    sell(products(:acme_nails), quantity: 4, fundi: nil)
    accounts(:acme).update!(fundi_commission_percent: 0)
    sell(products(:acme_nails), quantity: 4)
    assert_empty FundiEntry.all
  end

  test "an inactive fundi can't be named on a sale" do
    sale = @shift.current_sale
    assert_raises(ActiveRecord::RecordInvalid) { sale.change_fundi(fundis(:acme_old_plumber)) }
  end

  test "paying in cash takes it from a till as a payout, and no one can be paid more than they're owed" do
    sell(products(:acme_nails), quantity: 40) # 10,000.00
    owed = @fundi.balance_cents

    too_much = accounts(:acme).fundi_payouts.new(fundi: @fundi, amount_cents: owed + 1, payment_method: "cash", shift: @shift)
    assert_not too_much.save
    assert_match "is more than", too_much.errors.full_messages.to_sentence

    payout = accounts(:acme).fundi_payouts.create!(fundi: @fundi, amount_cents: owed, payment_method: "cash", shift: @shift)
    assert_equal [ "payout", owed, "Commission to Otieno Ouma" ], [ payout.cash_movement.kind, payout.cash_movement.amount_cents, payout.cash_movement.reason ]
    assert_equal 0, @fundi.balance_cents
    assert_equal [ "earned", "paid" ], @fundi.entries.chronologically.pluck(:kind)
  end

  test "M-Pesa needs its code, and cash needs an open till" do
    sell(products(:acme_nails), quantity: 4)
    mpesa = accounts(:acme).fundi_payouts.new(fundi: @fundi, amount_cents: 100, payment_method: "mobile_money")
    assert_not mpesa.save
    mpesa.reference = "sgh12abc34"
    assert mpesa.save
    assert_equal "SGH12ABC34", mpesa.reference

    cash = accounts(:acme).fundi_payouts.new(fundi: @fundi, amount_cents: 100, payment_method: "cash")
    assert_not cash.save
    assert_match "Choose the till", cash.errors.full_messages.to_sentence
  end

  test "an order names its fundi, and collecting it carries them to the sale" do
    order = accounts(:acme).customer_orders.create!(branch: branches(:acme_main), customer: customers(:acme_contractor), fundi: @fundi, status: "ordered",
      lines_attributes: [ { product: products(:acme_nails), quantity: 4, unit_price_cents: 25000 } ])
    sale = @shift.current_sale
    assert order.load_into(sale), order.errors.full_messages.to_sentence
    assert_equal @fundi, sale.reload.fundi
  end
end
