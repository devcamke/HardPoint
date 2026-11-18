require "test_helper"

# Who approved what for whom, and what a manager approved for themselves.
class ApprovalsReportTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:carl))
    memberships(:sara_acme).update!(role: "manager")
    stock_up products(:acme_nails), 100
  end

  def sale
    sale = shifts(:acme_front_open).current_sale
    sale.add(products(:acme_nails), quantity: 4)
    assert sale.pay(tender: "cash", tendered_cents: 1000_00).persisted?
    sale
  end

  def report = Report::Approvals.new(account: accounts(:acme), period: Report::Period.new(from: Date.current, to: Date.current))

  test "pairs of who asked and who approved, with self-approvals as their own" do
    sale.void(reason: "Rung up twice", by: users(:carl), approver: users(:amina))
    value = sale.tap { _1.void(reason: "Wrong customer", by: users(:sara), approver: users(:sara)) }.total_cents
    StockWriteOff.new(product: products(:acme_cement), branch: branches(:acme_main), quantity: 10, reason: "damaged", by: users(:sara)).approved(users(:sara))

    pairs, own = report.sections
    assert_equal [ [ "Sara Stockclerk", "Themselves", 2, value + 7000_00 ], [ "Carl Cashier", "Amina Owner", 1, value ] ], pairs.rows
    assert_equal [ [ "Sara Stockclerk", "Void", value ], [ "Sara Stockclerk", "Stock written off", 7000_00 ] ], own.rows.map { _1.values_at(1, 2, 4) }
  end

  test "the morning email says what each manager approved for themselves, but not owners" do
    sale.void(reason: "Wrong customer", by: users(:sara), approver: users(:sara))
    sale.void(reason: "Mine", by: users(:amina), approver: users(:amina))
    sale.update_columns(completed_at: 1.day.ago)
    Event.update_all(created_at: 1.day.ago)

    summary = OwnerSummary::Daily.new(accounts(:acme), Date.yesterday)
    assert_equal [ [ "Sara Stockclerk", 1, { "Void" => 1 } ] ], summary.own_approvals.map { [ _1.name, _1.count, _1.kinds ] }

    mail = ReportsMailer.with(account: accounts(:acme), date: Date.yesterday).daily_summary
    assert_match "Approved for themselves", mail.html_part.body.to_s
    assert_match(/Sara Stockclerk approved 1 of their own action \(KES .+\): 1 × void/, mail.text_part.body.to_s)
  end
end
