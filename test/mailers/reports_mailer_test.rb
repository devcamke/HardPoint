require "test_helper"

class ReportsMailerTest < ActionMailer::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:carl))
  end

  def sell_yesterday
    sale = shifts(:acme_front_open).current_sale
    sale.add(products(:acme_nails), quantity: 4)
    sale.pay(tender: "cash")
    sale.update_columns(completed_at: 1.day.ago)
  end

  test "each morning, yesterday's figures go to owners and managers who want them" do
    sell_yesterday
    Current.reset

    assert_enqueued_emails 1 do
      Account.without_isolation { Account.send_daily_summaries }
    end

    Account.without_isolation do
      Current.set(account: accounts(:acme)) do
        mail = ReportsMailer.with(account: accounts(:acme), date: Time.use_zone(accounts(:acme).time_zone) { Time.zone.yesterday }).daily_summary
        assert_equal [ "amina@acme.test" ], mail.to
        assert_match "KES 1,000.00 taken", mail.subject
        assert_match "Wire nails 3 inch", mail.text_part.body.to_s
      end
    end
  end

  test "how it was paid shows each method the shop used, and only those" do
    sell_yesterday

    Account.without_isolation do
      Current.set(account: accounts(:acme)) do
        html = ReportsMailer.with(account: accounts(:acme), date: Time.use_zone(accounts(:acme).time_zone) { Time.zone.yesterday }).daily_summary.html_part.body.to_s
        assert_match %r{<td>Cash</td><td style="text-align:right;">KES 1,000.00</td>}, html
        %w[ Foreign\ cash Points Airtel\ Money M-Pesa ].each { assert_no_match %r{<td>#{_1}</td>}, html }
      end
    end
  end

  test "nothing is sent after a day without sales, or to people who turned it off" do
    Account.without_isolation { accounts(:acme).send_daily_summary }
    assert_no_enqueued_emails

    sell_yesterday
    Account.without_isolation { memberships(:amina_acme).update!(daily_summary: false) }
    assert_no_enqueued_emails { accounts(:acme).send_daily_summary }
  end
end
