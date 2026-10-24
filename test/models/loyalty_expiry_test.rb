require "test_helper"

class LoyaltyExpiryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Current.account = @account = accounts(:acme)
    @customer = customers(:acme_walk_in)
    travel_to Time.zone.local(2025, 1, 10, 9)
    @program = @account.create_loyalty_program!(enabled: true, points_per_100: 1, point_value_cents: 100, expiry_months: 6)
  end

  def entry(points, on:)
    travel_to(on) { @customer.loyalty_entries.create!(account: @account, kind: "adjusted", points: points, note: "test") }
  end

  def run_expiry(on:)
    travel_to(on) { LoyaltyProgram.expire_points }
    Current.account = @account
  end

  test "points run out at the end of the month expiry_months after the month they're earned in, oldest used first" do
    entry 100, on: Time.zone.local(2025, 1, 20)
    entry 50, on: Time.zone.local(2025, 3, 5)
    entry(-30, on: Time.zone.local(2025, 4, 1))

    assert_equal [ [ Date.new(2025, 7, 31), 70 ], [ Date.new(2025, 9, 30), 50 ] ], @program.expiry_schedule(@customer)

    run_expiry on: Time.zone.local(2025, 7, 31, 12)
    assert_equal 120, @customer.points_balance, "not until the month is over"

    run_expiry on: Time.zone.local(2025, 8, 1, 6)
    run_expiry on: Time.zone.local(2025, 8, 2, 6)
    assert_equal 50, @customer.points_balance, "expired once, however often the job runs"
    expired = @customer.loyalty_entries.find_by!(kind: "expired")
    assert_equal [ -70, "Expired, earned before 1 February 2025" ], [ expired.points, expired.description ]

    run_expiry on: Time.zone.local(2025, 10, 1, 6)
    assert_equal 0, @customer.points_balance
    assert_empty @program.expiry_schedule(@customer)
  end

  test "points held when expiry is turned on or shortened count from that day" do
    @program.update!(expiry_months: nil)
    entry 100, on: Time.zone.local(2023, 5, 1)

    travel_to(Time.zone.local(2025, 2, 14)) { @program.update!(expiry_months: 12) }
    assert_equal Date.new(2025, 2, 14), @program.expiry_starts_on
    run_expiry on: Time.zone.local(2025, 3, 1)
    assert_equal 100, @customer.points_balance
    assert_equal [ [ Date.new(2026, 2, 28), 100 ] ], @program.expiry_schedule(@customer)

    travel_to(Time.zone.local(2025, 6, 3)) { @program.update!(expiry_months: 24) }
    assert_equal Date.new(2025, 2, 14), @program.reload.expiry_starts_on, "lengthening keeps the start"
    travel_to(Time.zone.local(2025, 7, 3)) { @program.update!(expiry_months: 6) }
    assert_equal Date.new(2025, 7, 3), @program.reload.expiry_starts_on

    run_expiry on: Time.zone.local(2026, 2, 1)
    assert_equal 0, @customer.points_balance
  end

  test "a switched-off scheme, or one without expiry, expires nothing" do
    entry 100, on: Time.zone.local(2025, 1, 20)
    @program.update!(enabled: false)
    run_expiry on: Time.zone.local(2026, 1, 1)
    @program.update!(enabled: true, expiry_months: nil)
    run_expiry on: Time.zone.local(2026, 1, 1)
    assert_equal 100, @customer.points_balance
  end

  test "customers are warned once in the last fortnight of the month their points run out" do
    @account.update!(sms_enabled: true)
    @program.update!(text_points: true)
    entry 100, on: Time.zone.local(2025, 1, 20)

    run_expiry on: Time.zone.local(2025, 7, 10, 6)
    assert_equal 0, @account.sms_messages.count, "too early"

    run_expiry on: Time.zone.local(2025, 7, 20, 6)
    run_expiry on: Time.zone.local(2025, 7, 21, 6)
    text = @account.sms_messages.sole
    assert_equal [ "points_expiring", "254733000222" ], [ text.purpose, text.recipient ]
    assert_equal "Acme Hardware: 100 of your points (worth KES 100.00) expire on 31 July 2025. Spend them at the till before then.", text.body
  end

  test "sales text what was earned when the shop texts about points" do
    @account.update!(sms_enabled: true)
    @program.update!(text_points: true)
    Current.session = @account.sessions.create!(user: users(:amina))
    sale = shifts(:acme_front_open).current_sale
    sale.change_customer(@customer)
    sale.add(products(:acme_cement)) # 800.00
    sale.pay(tender: "card", reference: "VISA 1")

    text = @account.sms_messages.sole
    assert_equal "points_earned", text.purpose
    assert_equal "Acme Hardware: you earned 8 points on receipt #{sale.reload.receipt_number}. You have 8 points, worth KES 8.00. " \
      "8 expire on 31 July 2025.", text.body

    assert_equal "Acme Hardware: You have 8 points, worth KES 8.00. 8 expire on 31 July 2025. Spend them at the till like cash.",
      Sms::Message.points_balance(@customer).body
  end
end
