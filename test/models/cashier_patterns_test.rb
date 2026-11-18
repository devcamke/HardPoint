require "test_helper"

# Each cashier against their own usual: a day that stands well out from their last eight weeks is flagged.
class CashierPatternsTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:carl))
    @shift = shifts(:acme_front_open)
    stock_up products(:acme_nails), 1000
    @today = Time.use_zone(accounts(:acme).time_zone) { Time.zone.yesterday }
  end

  def at(day) = Time.use_zone(accounts(:acme).time_zone) { day.in_time_zone.change(hour: 12) }

  # A cash sale on a day; voided (on that day) when asked.
  def sale_on(day, discount_cents: 0, voided: false, quantity: 1)
    sale = @shift.current_sale
    sale.add(products(:acme_nails), quantity: quantity)
    sale.update!(discount_cents: discount_cents, discount_approver: users(:amina), approved_discount_percent: 100) if discount_cents.positive?
    sale.recalculate
    assert sale.pay(tender: "cash", tendered_cents: 1000_00).persisted?
    sale.void(reason: "Rung up twice", by: users(:carl)) if voided
    sale.update_columns(completed_at: at(day), voided_at: (at(day) if voided))
    sale
  end

  # Twelve ordinary working days before the day: a sale each, and a void every fourth day.
  def usual_weeks
    (1..12).each { |back| sale_on(@today - back * 3, voided: (back % 4).zero?) }
  end

  def flags = CashierPatterns.new(accounts(:acme), @today).flags

  test "a day of voids well above the cashier's usual is flagged, with what's usual" do
    usual_weeks
    4.times { sale_on(@today, voided: true) }

    flag = flags.sole
    assert_equal [ users(:carl), :voids, 4 ], [ flag.cashier, flag.metric.key, flag.value ]
    assert_equal "voided 4 sales (usually under one a day)", flag.description
  end

  test "the morning email says when a cashier's day was unusual for them" do
    usual_weeks
    4.times { sale_on(@today, voided: true) }
    mail = ReportsMailer.with(account: accounts(:acme), date: @today).daily_summary
    assert_match "Unusual for the cashier", mail.html_part.body.to_s
    assert_match "Voided 4 sales (usually under one a day)", mail.html_part.body.to_s
    assert_match "Unusual: Carl Cashier voided 4 sales", mail.text_part.body.to_s
  end

  test "small numbers aren't flagged, however unusual" do
    usual_weeks
    2.times { sale_on(@today, voided: true) } # under the floor of 3
    assert_empty flags
  end

  test "a cashier without ten working days yet has no usual, and isn't flagged" do
    (1..5).each { |back| sale_on(@today - back) }
    5.times { sale_on(@today, voided: true) }
    assert_empty flags
  end

  test "discounts are judged against the cashier's own discounting" do
    (1..12).each { |back| sale_on(@today - back * 3, discount_cents: 50_00) } # KES 50 a day, usually
    sale_on(@today, discount_cents: 1500_00, quantity: 10)
    flag = flags.sole
    assert_equal :discount_cents, flag.metric.key
    assert_match(/gave KES 1,500.00 in discounts \(usually about KES 50.00 a day\)/, flag.description)
  end

  test "the drawer opened again and again without a sale is flagged" do
    usual_weeks
    sale_on(@today)
    4.times do
      registers(:acme_front).track_event "drawer_opened", reason: "Other", shift: @shift.name
    end
    Event.where(action: "drawer_opened").update_all(created_at: at(@today))
    assert_equal [ :drawer_openings ], flags.map { _1.metric.key }
    assert_match "opened the drawer without a sale 4 times", flags.first.description
  end

  test "goods taken off sales before payment, well above the cashier's usual, are flagged" do
    usual_weeks
    sale = @shift.current_sale
    sale.add(products(:acme_nails), quantity: 500)
    value = sale.reload.total_cents
    assert_operator value, :>=, 2000_00
    assert sale.discard
    Event.where(action: "sale_cleared").update_all(created_at: at(@today))
    sale_on(@today)

    flag = flags.sole
    assert_equal [ users(:carl), :taken_off_cents, value ], [ flag.cashier, flag.metric.key, flag.value ]
    assert_equal "took #{Money.format(value)} of goods off sales before payment (usually none)", flag.description
  end

  test "payouts from the till well above the cashier's usual are flagged" do
    usual_weeks
    sale_on(@today)
    @shift.cash_movements.create!(kind: "payout", amount_cents: 4000_00, reason: "Transport").update_columns(created_at: at(@today))

    flag = flags.sole
    assert_equal [ users(:carl), :payout_cents, 4000_00 ], [ flag.cashier, flag.metric.key, flag.value ]
    assert_equal "paid out KES 4,000.00 from the till (usually none)", flag.description
  end

  test "the morning email names a cashier whose till keeps closing a little short" do
    register = registers(:acme_front)
    @shift.update_columns(status: "closed", closed_at: at(@today - 20), expected_cash_cents: 5000_00, counted_cash_cents: 4700_00)
    [ 15, 10, 5, 0 ].each_with_index do |back, index|
      short = index == 1 ? 0 : 300_00 # one of the five balanced
      accounts(:acme).shifts.create!(register: register, opened_by: users(:carl), opened_at: at(@today - back) - 4.hours)
        .update_columns(status: "closed", closed_at: at(@today - back), expected_cash_cents: 5000_00, counted_cash_cents: 5000_00 - short)
    end

    pattern = OwnerSummary::Daily.new(accounts(:acme), @today).small_and_often.sole
    assert_equal [ "Carl Cashier", "closed short on 4 of their last 5 shifts, KES 1,200.00 in all" ], [ pattern.name, pattern.words ]
    assert_empty OwnerSummary::Daily.new(accounts(:acme), @today - 10).small_and_often, "not on a day their till balanced"
  end

  test "the morning email names whoever cut a payout to fit under the approval limit" do
    2.times { @shift.cash_movements.create!(kind: "payout", amount_cents: 4800_00, reason: "Transport").update_columns(created_at: at(@today)) }
    @shift.cash_movements.create!(kind: "payout", amount_cents: 500_00, reason: "Lunch").update_columns(created_at: at(@today))

    summary = OwnerSummary::Daily.new(accounts(:acme), @today)
    assert_equal [ "made 2 payouts just under the KES 5,000.00 that needs approval, KES 9,600.00 in all" ], summary.small_and_often.map(&:words)

    sale_on(@today)
    mail = ReportsMailer.with(account: accounts(:acme), date: @today).daily_summary
    assert_match "Small and often", mail.html_part.body.to_s
    assert_match "Small and often: Carl Cashier made 2 payouts just under", mail.text_part.body.to_s
  end
end
