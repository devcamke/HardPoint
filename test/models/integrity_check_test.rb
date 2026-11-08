require "test_helper"

class IntegrityCheckTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:carl))
    @shift = shifts(:acme_front_open)
  end

  def sell(quantity: 2)
    @shift.current_sale.tap { _1.add(products(:acme_nails), quantity: quantity); _1.pay(tender: "cash") }
  end

  test "a shop whose books add up has no findings" do
    sell
    sell
    assert IntegrityCheck.run.clean?, IntegrityCheck.run.findings.map(&:description).inspect
  end

  test "a deleted sale, a stock level off the ledger, a short-paid sale, an uncounted shift and unmatched money are found" do
    first = sell
    sell
    third = sell
    Account.without_isolation do
      first.payments.delete_all
      first.lines.delete_all
      first.delete # leaves a hole in the receipt numbers
      third.payments.first.update_columns(amount_cents: third.payments.first.amount_cents - 100)
      stock_levels(:acme_main_cement).update_columns(quantity: 49)
      @shift.update_columns(status: "closed", closed_at: Time.current, counted_cash_cents: nil) # closed without a count
      accounts(:acme).mpesa_transactions.create!(shortcode: accounts(:acme).mpesa_shortcodes.create!(name: "Paybill", shortcode: "174379", environment: "simulator"),
        source: Mpesa::Transaction::SOURCES.first, trans_id: "ABC123XYZ", amount_cents: 500_00, phone: "254722000111", payer_name: "Someone", transacted_at: 2.days.ago)
    end

    check = IntegrityCheck.run
    found = check.findings.group_by(&:check).transform_values { _1.sole }
    assert_equal %i[ receipt_gaps stock_mismatch unbalanced_sales uncounted_shifts unmatched_mpesa ], found.keys.sort_by(&:to_s).sort
    assert_equal "1 receipt number missing at branch #{branches(:acme_main).id}", found[:receipt_gaps].detail
    assert_match "49.0 on hand, ledger 50.0", found[:stock_mismatch].detail
    assert_match "paid #{third.total_cents - 100}", found[:unbalanced_sales].detail
    assert_equal 1, found[:uncounted_shifts].count
    assert_match "1 M-Pesa payment (KES 500.00) matched to nothing", found[:unmatched_mpesa].detail
    assert_match "Acme Hardware (acme):\n  - Receipt gaps:", check.summary
  end

  test "the nightly job remembers the run and tells the operators about findings" do
    store, Rails.cache = Rails.cache, ActiveSupport::Cache::MemoryStore.new
    sell
    assert_no_difference -> { ActionMailer::Base.deliveries.size } do
      IntegrityCheckJob.perform_now
    end
    assert_empty IntegrityCheck.last[:findings]
    assert_equal :ok, PlatformHealth.check.checks.find { _1.name == :integrity }.status

    Account.without_isolation { stock_levels(:acme_main_cement).update_columns(quantity: 1) }
    assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
      IntegrityCheckJob.perform_now
    end
    assert_match "Data integrity: 1 finding across 1 shop", ActionMailer::Base.deliveries.last.subject
    assert_match "stock on hand isn't the sum of the ledger", ActionMailer::Base.deliveries.last.body.to_s
    assert_equal [ :warning, "1 finding last night: Stock mismatch" ], PlatformHealth.check.checks.find { _1.name == :integrity }.then { [ _1.status, _1.detail ] }

    travel 2.days do
      assert PlatformHealth.check.checks.find { _1.name == :integrity }.failing?, "a run that's two days old means the job stopped"
    end
  ensure
    Rails.cache = store
  end
end
