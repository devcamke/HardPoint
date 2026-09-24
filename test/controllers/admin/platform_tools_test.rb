require "test_helper"

class Admin::PlatformToolsTest < ActionDispatch::IntegrationTest
  setup do
    host! "admin.localhost"
    sign_in_as_administrator
    @account = accounts(:acme)
  end

  def acme = Account.without_isolation { @account.reload }
  def acme_events(action) = Account.without_isolation { Event.where(account: @account, action: action).to_a }

  test "the shop list shows plans, status and usage, and filters by status" do
    Account.without_isolation { accounts(:bolt).update!(subscription_status: "read_only") }

    get admin_accounts_path
    assert_select "##{dom_id(@account)}", /Business/
    assert_select "##{dom_id(@account)}", /Trial, \d+ days left/

    get admin_accounts_path(status: "read_only")
    assert_select "td a", "Bolt & Nut Supplies"
    assert_select "td a", text: "Acme Hardware", count: 0
  end

  test "a shop's page has its subscription and the tools to manage it" do
    get admin_account_path(@account)
    assert_select "#subscription", /Change plan/
    assert_select "#subscription", /Extend trial by/
  end

  test "changing plan, extending the trial, suspending and restoring are all on the shop's record" do
    patch admin_account_plan_path(@account), params: { plan: "enterprise" }
    assert_equal "enterprise", acme.plan

    trial_ended = acme.trial_ends_at
    post admin_account_trial_extension_path(@account), params: { days: 14 }
    assert_in_delta trial_ended + 14.days, acme.trial_ends_at, 1.second

    post admin_account_suspension_path(@account), params: { reason: "Chargeback" }
    assert acme.suspended?
    assert_equal "Chargeback", acme.suspended_reason

    delete admin_account_suspension_path(@account)
    assert acme.trialing?

    assert_equal [ users(:ada).email_address ], acme_events("suspended").map { _1.particulars["administrator"] }
    assert_equal 1, acme_events("trial_extended").size
    assert_equal 1, acme_events("restored").size
  end

  test "recording a bank payment pays the open invoice" do
    invoice = Account.without_isolation { Current.set(account: @account) { @account.start_subscription_now } }

    post admin_account_payments_path(@account), params: { reference: "EFT 20260924" }
    assert Account.without_isolation { invoice.reload.paid? }
    assert acme.active?
    assert_equal "EFT 20260924", Account.without_isolation { invoice.payments.succeeded.last.receipt }
  end

  test "announcements appear in every shop until they end" do
    post admin_announcements_path, params: { announcement: { title: "Maintenance on Sunday", level: "warning", starts_at: 1.hour.ago } }
    assert_redirected_to admin_announcements_path
    announcement = Announcement.last

    sign_in_as users(:amina), account: @account
    get root_path
    assert_select "##{dom_id(announcement)}", /Maintenance on Sunday/

    announcement.update!(ends_at: 1.minute.ago, starts_at: 2.hours.ago)
    get root_path
    assert_select "##{dom_id(announcement)}", count: 0
  end

  test "support requests from every shop, marked resolved" do
    request = Account.without_isolation do
      Current.set(account: @account) { @account.support_requests.create!(user: users(:carl), subject: "Printer", body: "Blank receipts") }
    end

    get admin_support_requests_path
    assert_select "##{dom_id(request)}", /Blank receipts/

    patch admin_support_request_path(request, status: "resolved")
    assert Account.without_isolation { request.reload.resolved? }
  end
end
