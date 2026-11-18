require "test_helper"

# Writing stock off by hand past the shop's daily limit needs an owner or manager (StockWriteOff).
class StockWriteOffsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    Account.without_isolation { memberships(:amina_acme).set_approval_pin("2468") }
    sign_in_as users(:sara) # a stock clerk
    @cement = products(:acme_cement) # costs 700.00; the limit is 5,000.00 a day
  end

  def in_acme(&) = Account.without_isolation { Current.set(account: accounts(:acme)) { yield } }
  def on_hand = in_acme { @cement.stock_at(branches(:acme_main)) }

  def adjust(quantity, reason: "damaged", **extra)
    post stock_adjustments_path, params: { stock_adjustment: { product_id: @cement.id, branch_id: branches(:acme_main).id, reason: reason, quantity: quantity }, **extra }
  end

  test "a clerk writes off a little alone, and is asked for a PIN once the day's total passes the limit" do
    get new_stock_adjustment_path(product_id: @cement.id)
    assert_select "input[name=approval_pin]"

    assert_difference -> { on_hand }, -4 do
      adjust "-4" # 2,800.00
    end
    assert_redirected_to product_path(@cement)

    assert_no_difference -> { on_hand } do
      adjust "-4" # 5,600.00 with the first
    end
    assert_response :unprocessable_entity
    assert_select "li", /writes off KES 2,800.00 at cost \(KES 2,800.00 already today\).+more than KES 5,000.00 in a day needs a manager's approval PIN/

    assert_no_difference -> { on_hand } do
      adjust "-4", approval_pin: "0000"
    end
  end

  test "with a manager's PIN it goes through, is kept in Activity, and the owners are emailed" do
    Account.without_isolation { memberships(:carl_acme).update!(role: "manager") } # someone besides the approver to tell
    assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob do
      assert_difference -> { on_hand }, -10 do
        adjust "-10", reason: "stolen", approval_pin: "2468"
      end
    end

    job = enqueued_jobs.last[:args]
    assert_equal [ "OwnerAlertsMailer", "large_write_off" ], job.first(2)
    assert_equal [ [ users(:carl).email_address ], 7000_00 ], job.last["params"].values_at("recipients", "value_cents")

    event = in_acme { @cement.events.find_by!(action: "write_off_approved") }
    assert_equal [ users(:sara), users(:amina).name, "stolen", 7000_00 ], [ event.creator, *event.particulars.values_at("approver", "reason", "value") ]

    mail = in_acme do
      OwnerAlertsMailer.with(record: @cement, recipients: [ "amina@acme.test" ], branch: branches(:acme_main), quantity: "10 bag", reason: "stolen",
        value_cents: 7000_00, today_cents: 7000_00, written_off_by: "Sara Stock", approver: "Amina Owner").large_write_off
    end
    assert_match "KES 7,000.00 of Bamburi cement 50kg was written off", mail.subject
    assert_match "Stock written off", mail.html_part.body.to_s
    assert_match "Approved by: Amina Owner", mail.text_part.body.to_s

    sign_in_as users(:amina)
    get events_path
    assert_match(/wrote off 10 .+ of Bamburi cement 50kg at Main branch as stolen \(KES 7,000.00 at cost\), approved by Amina/, response.body)
  end

  test "stock coming in needs no approval, and an owner approves their own" do
    assert_difference -> { on_hand }, 100 do
      adjust "100", reason: "found"
    end

    sign_in_as users(:amina)
    get new_stock_adjustment_path(product_id: @cement.id)
    assert_select "input[name=approval_pin]", count: 0
    assert_difference -> { on_hand }, -10 do
      adjust "-10"
    end
    assert in_acme { @cement.events.find_by!(action: "write_off_approved").particulars["self_approved"] }
  end

  test "writing off a batch counts towards the same limit" do
    batch = in_acme do
      Current.set(user: users(:amina)) do
        @cement.update!(tracks_batches: true)
        @cement.move_stock(branch: branches(:acme_main), quantity: 12, reason: "received", batch: { number: "X-1", expires_on: 3.days.ago.to_date })
        @cement.stock_batches.find_by!(number: "X-1")
      end
    end

    post stock_batch_write_off_path(batch), params: { quantity: "12", reason: "expired" } # 8,400.00
    assert_match "needs a manager's approval PIN", flash[:alert]
    assert_equal 12, in_acme { batch.reload.quantity }

    post stock_batch_write_off_path(batch), params: { quantity: "12", reason: "expired", approval_pin: "2468" }
    assert_equal 0, in_acme { batch.reload.quantity }
    assert in_acme { @cement.events.exists?(action: "write_off_approved") }
  end

  test "owners set the limit on Shop details" do
    sign_in_as users(:amina)
    get edit_account_path
    assert_select "input[name='account[write_off_approval_above]']"
    patch account_path, params: { account: { write_off_approval_above: "20,000" } }
    assert_equal 20_000_00, Account.without_isolation { accounts(:acme).reload.write_off_approval_above_cents }
  end
end
