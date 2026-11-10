require "test_helper"

# The owner's emails beyond the plain daily figures: what's worth a look each morning, the Monday summary,
# the instant alerts, and stock at zero that has no reorder level.
class OwnerEmailsTest < ActionMailer::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:carl))
    @shift = shifts(:acme_front_open)
    @main = branches(:acme_main)
  end

  def yesterday = Time.use_zone(accounts(:acme).time_zone) { Time.zone.yesterday }

  def sell(product, quantity:, completed_at: 1.day.ago)
    sale = @shift.current_sale
    sale.add(product, quantity: quantity)
    payment = sale.pay(tender: "cash")
    assert payment.persisted?, payment.errors.full_messages.to_sentence
    sale.update_columns(completed_at: completed_at)
    sale
  end

  def daily_html = ReportsMailer.with(account: accounts(:acme), date: yesterday).daily_summary.html_part.body.to_s

  test "the morning email says what the till turned away, what ran out and what was written off" do
    sell products(:acme_nails), quantity: 4
    pipe = products(:acme_pipe) # 3 on the shelf
    sale = @shift.current_sale
    assert sale.add(pipe, quantity: 5).errors.any?, "five is more than there is"
    StockRefusal.update_all(created_at: 1.day.ago)
    pipe.move_stock(branch: @main, quantity: -3, reason: "damaged")
    StockMovement.where(reason: "damaged").update_all(created_at: 1.day.ago)

    html = daily_html
    assert_match "Turned away at the till", html
    assert_match %r{#{pipe.name}<div[^>]*>5 pc wanted</div>}, html
    assert_match "1 product at zero at Main branch", html
    assert_match %r{Damaged<div[^>]*>1 item · Carl}, html
    assert_no_match "Nothing to chase", html
  end

  test "a quiet day says there's nothing to chase" do
    sell products(:acme_nails), quantity: 4
    assert_match "Nothing to chase", daily_html
  end

  test "each Monday the week goes to those who want it, with the weeks before and who owes what" do
    monday = Time.use_zone(accounts(:acme).time_zone) { Time.zone.today.beginning_of_week }
    sell products(:acme_nails), quantity: 4, completed_at: (monday - 2).in_time_zone.change(hour: 12)
    Current.reset

    assert_enqueued_emails 1 do
      travel_to monday.in_time_zone(accounts(:acme).time_zone).change(hour: 7) do
        Account.without_isolation { Account.send_weekly_summaries }
      end
    end

    Account.without_isolation do
      Current.set(account: accounts(:acme)) do
        mail = ReportsMailer.with(account: accounts(:acme), ends_on: monday - 1).weekly_summary
        assert_equal [ "amina@acme.test" ], mail.to
        assert_match "your week to", mail.subject
        html = mail.html_part.body.to_s
        assert_match "The last eight weeks", html
        assert_match "Wire nails 3 inch", html
      end
    end

    Account.without_isolation { memberships(:amina_acme).update!(weekly_summary: false) }
    assert_no_enqueued_emails { Account.without_isolation { accounts(:acme).send_weekly_summary(monday - 1) } }
  end

  test "a till closing short by more than the owner allows emails the owner straight away, not the cashier who closed it" do
    accounts(:acme).update!(alert_shift_short_above: 1000)
    expected = @shift.expected_cash_cents_now

    assert_enqueued_email_with OwnerAlertsMailer, :shift_short, params: ->(params) { params[:recipients] == [ "amina@acme.test" ] } do
      assert @shift.close(counted_cash_cents: expected - 1500_00, by: users(:carl))
    end

    mail = OwnerAlertsMailer.with(record: @shift.reload, recipients: [ "amina@acme.test" ], by: "Carl").shift_short
    assert_match "KES 1,500.00 short", mail.subject
    assert_match "Cash count short", mail.html_part.body.to_s
  end

  test "a till closing a little short waits for the morning email" do
    expected = @shift.expected_cash_cents_now
    assert_no_enqueued_emails do
      assert @shift.close(counted_cash_cents: expected - 50_00, by: users(:carl))
    end
  end

  test "voiding a completed sale over the limit, or approving a count that loses more than it, emails the owner" do
    accounts(:acme).update!(alert_void_above: 500, alert_count_loss_above: 100)
    sale = sell(products(:acme_nails), quantity: 4, completed_at: Time.current) # 1,000.00

    assert_enqueued_email_with OwnerAlertsMailer, :large_void, params: ->(params) { params[:record] == sale } do
      assert sale.void(reason: "Rung up twice", by: users(:carl))
    end
    assert_match "was voided", OwnerAlertsMailer.with(record: sale.reload, recipients: [ "amina@acme.test" ]).large_void.subject

    count = accounts(:acme).stock_counts.create!(branch: @main, creator: users(:sara))
    count.lines.find_by!(product: products(:acme_screws)).update!(counted_quantity: 900) # 100 short at 3.00
    count.submit
    assert_enqueued_email_with OwnerAlertsMailer, :count_loss, params: ->(params) { params[:record] == count } do
      assert count.approve(users(:carl))
    end
    assert_match "KES 300.00 short", OwnerAlertsMailer.with(record: count.reload, recipients: [ "amina@acme.test" ]).count_loss.subject
  end

  test "the low-stock email also lists what's at zero with no reorder level" do
    screws = products(:acme_screws)
    screws.update!(reorder_level: 0)
    screws.move_stock(branch: @main, quantity: -1000, reason: "damaged")

    mail = StockMailer.with(account: accounts(:acme)).low_stock_digest
    assert_match "Out of stock, and not on the reorder list", mail.html_part.body.to_s
    assert_match screws.name, mail.text_part.body.to_s
  end
end
