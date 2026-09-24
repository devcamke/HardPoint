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
    patch billing_plan_path, params: { plan: "enterprise" }
    assert_equal "enterprise", Account.without_isolation { @account.reload.plan }

    patch billing_plan_path, params: { plan: "starter" }
    assert_match "Starter allows", flash[:alert]
    assert_equal "enterprise", Account.without_isolation { @account.reload.plan }
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

  test "the invoice PDF" do
    post billing_subscription_start_path
    get billing_invoice_path(Account.without_isolation { @account.billing_invoices.last })
    assert_equal "application/pdf", response.media_type
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

    patch billing_plan_path, params: { plan: "enterprise" }
    assert_equal "enterprise", Account.without_isolation { @account.reload.plan }
  end

  test "a read-only shop answers the till's JSON with 402, but still takes offline sales" do
    read_only!
    post pos_mpesa_requests_path, as: :json
    assert_response :payment_required
  end
end
