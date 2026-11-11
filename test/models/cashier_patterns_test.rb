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
end
