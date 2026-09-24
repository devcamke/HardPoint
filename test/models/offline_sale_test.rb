require "test_helper"

class OfflineSaleTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:amina))
    @shift = shifts(:acme_front_open)
  end

  def payload(uuid: SecureRandom.uuid, lines: [ { product_id: products(:acme_nails).id, quantity: "4", unit_price_cents: 25000 } ],
              payments: [ { tender: "cash", tendered_cents: 100000 } ], total_cents: 100000, happened_at: 20.minutes.ago)
    { uuid: uuid, receipt_number: "MAIN-OFF1-0001", happened_at: happened_at.iso8601, shift_id: @shift.id, cashier_id: users(:carl).id,
      total_cents: total_cents, discount_cents: 0, lines: lines, payments: payments }
  end

  def record(data) = accounts(:acme).sales.record_offline(data)

  test "an offline sale is recorded as it happened, and sending it again records nothing new" do
    data = payload
    result = record(data)

    assert_equal "recorded", result.status
    sale = result.sale
    assert sale.completed?
    assert_equal "MAIN-000001", sale.receipt_number
    assert_equal "MAIN-OFF1-0001", sale.offline_receipt_number
    assert_equal users(:carl), sale.cashier
    assert_in_delta 20.minutes.ago, sale.completed_at, 2
    assert_equal 25.5 - 4, products(:acme_nails).stock_at(branches(:acme_main))
    assert_equal "recorded_offline", sale.events.last.action

    again = record(data)
    assert_equal [ "duplicate", sale ], [ again.status, again.sale ]
    assert_equal 1, accounts(:acme).sales.offline.count
  end

  test "worth a second look: prices since raised, stock below zero, a shift already closed" do
    products(:acme_pipe).update!(price_cents: 130000)
    @shift.close(counted_cash_cents: @shift.expected_cash_cents_now)

    result = record(payload(lines: [ { product_id: products(:acme_pipe).id, quantity: "5", unit_price_cents: 120000 } ],
      payments: [ { tender: "mobile_money", amount_cents: 600000, reference: "SJK4H7T2QP" } ], total_cents: 600000))

    assert_equal "recorded", result.status
    assert_includes result.warnings, "PVC pipe 2 inch 6m sold at KES 1,200.00; the price is now KES 1,300.00"
    assert_includes result.warnings, "PVC pipe 2 inch 6m now shows -2 in stock at Main branch"
    assert_match "had already closed", result.warnings.last
    assert_equal result.warnings, result.sale.events.last.particulars["warnings"]
  end

  test "a sale the payments don't cover is parked at its till for someone to finish" do
    result = record(payload(payments: [ { tender: "cash", tendered_cents: 50000 } ], total_cents: 100000))

    assert_equal "needs_attention", result.status
    assert result.sale.parked?
    assert_match "KES 500.00 is still due", result.warnings.join
  end

  test "the server's total is kept when the till worked it out differently" do
    result = record(payload(total_cents: 99000, payments: [ { tender: "cash", tendered_cents: 100000 } ]))
    assert_includes result.warnings, "The till worked out KES 990.00; the total is KES 1,000.00"
  end

  test "bad data is refused whole, and the till's clock isn't trusted beyond the shift" do
    assert_equal "error", record(payload(uuid: "not-a-uuid")).status
    broken = record(payload(lines: [ { product_id: 0, quantity: "1", unit_price_cents: 100 } ]))
    assert_equal "error", broken.status
    assert_equal 0, accounts(:acme).sales.offline.count

    future = record(payload(happened_at: 3.days.from_now))
    assert_operator future.sale.completed_at, :<=, 6.minutes.from_now
  end

  test "another shop's shift can't be named" do
    assert_equal "error", record(payload.merge(shift_id: Account.without_isolation { Shift.create!(account: accounts(:bolt),
      register: accounts(:bolt).registers.create!(account: accounts(:bolt), branch: branches(:bolt_main), name: "Counter")).id })).status
  end
end
