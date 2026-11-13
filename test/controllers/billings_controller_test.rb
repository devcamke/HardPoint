require "test_helper"

class BillingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:acme)
    sign_in_as users(:amina), account: @account
  end

  def read_only!
    Account.without_isolation { @account.update!(subscription_status: "read_only") }
  end

  test "the billing page shows the plan, usage and invoices" do
    get billing_path
    assert_response :success
    assert_select "h1", /Billing/
    assert_select "form[action=?]", billing_plan_path, minimum: 2
  end

  test "cashiers can't see billing" do
    sign_out
    sign_in_as users(:carl), account: @account
    get billing_path
    assert_response :forbidden
  end

  test "switching plan, and a smaller plan that doesn't fit is refused" do
    patch billing_plan_path, params: { plan: "unlimited" }
    assert_equal "unlimited", Account.without_isolation { @account.reload.plan }

    patch billing_plan_path, params: { plan: "starter" }
    assert_match "Starter allows", flash[:alert]
    assert_equal "unlimited", Account.without_isolation { @account.reload.plan }
  end

  test "buying an extra till and choosing yearly billing" do
    patch billing_add_ons_path, params: { account: { extra_registers: 1, extra_branches: 0, billing_interval: "yearly" } }
    assert_redirected_to billing_path
    assert_match "KES 38,000.00 for a year", flash[:notice]
    assert_equal [ 1, "yearly" ], Account.without_isolation { @account.reload.values_at(:extra_registers, :billing_interval) }

    get billing_path
    assert_select "#add_ons", /Your next invoice: KES 38,000.00 for a year/
    assert_select "#add_ons input[name='account[extra_registers]'][value='1']"
  end

  test "an extra till bought partway through a paid month is invoiced for the rest of it" do
    Account.without_isolation { @account.update!(subscription_status: "active", current_period_ends_at: 15.days.from_now) }
    patch billing_add_ons_path, params: { account: { extra_registers: 1, extra_branches: 0, billing_interval: "monthly" } }
    invoice = Account.without_isolation { @account.billing_invoices.one_off.last }
    assert_match "Invoice #{invoice.number} for KES #{invoice.amount}", flash[:notice]
    assert_match "covers the rest of this period", flash[:notice]
    assert_match "1 extra till added", invoice.description
  end

  test "giving back an extra that's in use is refused" do
    Account.without_isolation { @account.update!(plan: "starter", extra_branches: 1) }
    patch billing_add_ons_path, params: { account: { extra_registers: 0, extra_branches: 0, billing_interval: "monthly" } }
    assert_match "more than 1 branch in use", flash[:alert]
    assert_equal 1, Account.without_isolation { @account.reload.extra_branches }
  end

  test "ending the trial early issues the first invoice, payable by M-Pesa prompt" do
    post billing_subscription_start_path
    invoice = Account.without_isolation { @account.billing_invoices.last }
    assert invoice.open?

    post billing_mpesa_payments_path, params: { phone: "0722 000 111" }
    assert_redirected_to billing_path
    payment = Account.without_isolation { invoice.payments.last }
    assert_equal "mpesa", payment.provider

    get billing_mpesa_payment_path(payment), as: :json
    assert_includes %w[ pending succeeded ], response.parsed_body["status"]
  end

  test "a card payment through the simulated checkout" do
    post billing_subscription_start_path
    post billing_card_payments_path
    reference = Account.without_isolation { @account.billing_payments.last.reference }
    assert_redirected_to billing_card_simulator_path(reference: reference)

    post billing_card_simulator_path(reference: reference)
    assert Account.without_isolation { @account.reload.active? }
  end

  test "the invoice PDF, with add-ons, yearly, and for a one-off" do
    Account.without_isolation { @account.update!(extra_registers: 2, billing_interval: "yearly") }
    post billing_subscription_start_path
    invoice = Account.without_isolation { @account.billing_invoices.subscription.last }
    assert_equal 3_500_00 * 10 + 300_00 * 2 * 10, invoice.amount_cents
    get billing_invoice_path(invoice)
    assert_equal "application/pdf", response.media_type

    setup = Account.without_isolation { Current.set(account: @account) { @account.issue_one_off_invoice("Setup and training visit", 15_000_00) } }
    get billing_invoice_path(setup)
    assert_equal "application/pdf", response.media_type

    get billing_path
    assert_select "td", /Setup and training visit/
  end

  test "a read-only shop can be looked at and paid, but not changed" do
    read_only!

    get products_path
    assert_response :success
    assert_select "#subscription_banner", /read-only/

    assert_no_difference -> { Account.without_isolation { @account.branches.count } } do
      post branches_path, params: { branch: { name: "Westlands" } }
    end
    assert_match "read-only until the HardPoint invoice is paid", flash[:alert]

    patch billing_plan_path, params: { plan: "unlimited" }
    assert_equal "unlimited", Account.without_isolation { @account.reload.plan }
  end

  test "a read-only shop answers the till's JSON with 402, but still takes offline sales" do
    read_only!
    post pos_mpesa_requests_path, as: :json
    assert_response :payment_required
  end
end
