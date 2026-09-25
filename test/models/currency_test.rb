require "test_helper"

class CurrencyTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:amina))
    @usd = accounts(:acme).currencies.create!(code: "usd", rate: "129.5")
    @ugx = accounts(:acme).currencies.create!(code: "UGX", rate: "0.0348")
    @shift = shifts(:acme_front_open)
  end

  def sale_of(product = products(:acme_cement), quantity: 1)
    @shift.current_sale.tap { _1.add(product, quantity: quantity) }
  end

  test "rates convert down to the cent, whole-shilling currencies print whole" do
    assert_equal "USD", @usd.code
    assert_equal 2590_00, @usd.to_base_cents(20_00)
    assert_equal 1736, @ugx.to_base_cents(499_00), "UGX 499 is KES 17.3652, rounded down"
    assert_equal "UGX 50,000", Money.format(50_000_00, currency: "UGX")
    assert_not accounts(:acme).currencies.new(code: "KES", rate: 1).valid?, "not the shop's own currency"
  end

  test "foreign notes pay at the shop's rate, with change in the shop's currency" do
    sale = sale_of # 800.00
    payment = sale.pay(tender: "foreign_cash", currency: "USD", foreign_tendered_cents: 10_00)

    assert sale.reload.completed?
    assert_equal [ 1295_00, 800_00, 495_00 ], [ payment.tendered_cents, payment.amount_cents, payment.change_cents ]
    assert_equal [ "USD", 129.5 ], [ payment.currency, payment.exchange_rate.to_f ]
    assert_match "USD 10.00 cash @ 129.5", payment.label

    @usd.update!(rate: 140)
    assert_equal 129.5, payment.reload.exchange_rate.to_f, "the payment keeps its rate"
  end

  test "part in foreign notes, the rest in shillings; unknown currencies are refused" do
    sale = sale_of(quantity: 2) # 1,600.00
    refused = sale.pay(tender: "foreign_cash", currency: "EUR", foreign_tendered_cents: 5_00)
    assert_match "isn't taken at the till", refused.errors.full_messages.to_sentence

    sale.pay(tender: "foreign_cash", currency: "UGX", foreign_tendered_cents: 20_000_00)
    assert_equal 1600_00 - 696_00, sale.balance_due_cents
    sale.pay(tender: "cash", tendered_cents: 1000_00)
    assert sale.reload.completed?
  end

  test "the drawer: shilling change comes out of the float, foreign notes are counted apart" do
    sale_of.pay(tender: "foreign_cash", currency: "USD", foreign_tendered_cents: 10_00)
    before = 5000_00

    assert_equal before - 495_00, @shift.expected_cash_cents_now
    assert_equal({ "USD" => 10_00 }, @shift.expected_foreign_cents_now)
    assert_equal %w[ UGX USD ], @shift.currencies_to_count

    @shift.close(counted_cash_cents: before - 495_00, counted_foreign_cents: { "USD" => 5_00 })
    assert_equal({ "USD" => { "expected" => 10_00, "counted" => 5_00 } }, @shift.reload.foreign_cash)
    assert_equal 0, @shift.variance_cents
  end
end
