require "test_helper"

class LoyaltyControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:acme)
    sign_in_as users(:amina), account: @account
  end

  def acme(&) = Account.without_isolation(&)

  test "switch it on, earn at the till, spend it, adjust it" do
    get edit_loyalty_program_path
    assert_response :success
    patch loyalty_program_path, params: { loyalty_program: { enabled: "1", points_per_100: "5", point_value: "1", min_redeem_points: "10" } }
    assert acme { @account.reload.loyalty_program.enabled? }

    post pos_till_path, params: { register_id: registers(:acme_front).id }
    patch pos_customer_path, params: { customer_id: customers(:acme_contractor).id }, as: :turbo_stream
    post pos_lines_path, params: { code: "NAIL-3" }, as: :turbo_stream
    post pos_payments_path, params: { tender: "card", reference: "VISA 1" }
    sale = acme { @account.sales.completed.last }
    get sale_receipt_path(sale)
    assert_match "Points earned", response.body
    assert_equal 12, acme { customers(:acme_contractor).points_balance }, "KES 240 contractor price at 5 per 100"

    patch pos_customer_path, params: { customer_id: customers(:acme_contractor).id }, as: :turbo_stream
    post pos_lines_path, params: { code: "NAIL-3" }, as: :turbo_stream
    assert_select "input[name=tender][value=points]"
    post pos_payments_path, params: { tender: "points", amount: "" }, as: :turbo_stream
    assert_equal 0, acme { customers(:acme_contractor).points_balance }

    post customer_loyalty_adjustments_path(customers(:acme_contractor)), params: { points: "25", note: "Sorry for the wait" }
    assert_equal 25, acme { customers(:acme_contractor).points_balance }
    get customer_path(customers(:acme_contractor))
    assert_select "#loyalty_points", /Adjusted: Sorry for the wait/
  end

  test "expiry and texts are set in the scheme, and a customer's balance can be texted" do
    acme { @account.update!(sms_enabled: true) }
    patch loyalty_program_path, params: { loyalty_program: { enabled: "1", points_per_100: "1", point_value: "1", min_redeem_points: "10",
      expiry_months: "12", text_points: "1" } }
    program = acme { @account.loyalty_program.reload }
    assert_equal [ 12, true, acme { program.local_today } ], [ program.expiry_months, program.text_points, program.expiry_starts_on ]
    get edit_loyalty_program_path
    assert_select "p", /Running out at the end of this month/

    post customer_loyalty_adjustments_path(customers(:acme_contractor)), params: { points: "40", note: "Welcome" }
    get customer_path(customers(:acme_contractor))
    assert_select "#loyalty_points", /40 points\s+expire on/
    post customer_points_text_path(customers(:acme_contractor))
    assert_redirected_to customer_path(customers(:acme_contractor), anchor: "loyalty_points")
    assert_match "You have 40 points", acme { @account.sms_messages.sole.body }
  end

  test "cashiers can't change the scheme or adjust points" do
    sign_in_as users(:carl), account: @account
    get edit_loyalty_program_path
    assert_response :forbidden
    post customer_loyalty_adjustments_path(customers(:acme_contractor)), params: { points: "1000", note: "Me" }
    assert_response :forbidden
  end
end
