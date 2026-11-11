require "test_helper"

class CreditHoldsTest < ActionDispatch::IntegrationTest
  setup do
    @customer = customers(:acme_contractor)
    in_acme do
      accounts(:acme).update!(credit_hold_after_days: 15)
      stock_up products(:acme_nails), 50
      sale = shifts(:acme_front_open).current_sale
      sale.change_customer(@customer)
      sale.add(products(:acme_nails), quantity: 4)
      assert sale.pay(tender: "on_account").persisted?
      sale.update_columns(completed_at: 60.days.ago)
    end
  end

  def in_acme(&) = Account.without_isolation { Current.set(account: accounts(:acme), user: users(:amina)) { yield } }

  test "the customer's page says the account is on hold, and a manager lifts it with a reason" do
    sign_in_as users(:amina)
    get customer_path(@customer)
    assert_select "#credit-hold h2", "On hold"
    assert_select "#credit-hold", /KES 1,000.00 is more than 15 days overdue/

    post customer_credit_hold_lift_path(@customer), params: { days: "14", reason: "Cheque on Friday" }
    follow_redirect!
    assert_select "#credit-hold", /Hold lifted until .* by Amina.*: Cheque on Friday/

    delete customer_credit_hold_lift_path(@customer)
    follow_redirect!
    assert_select "#credit-hold h2", "On hold"
  end

  test "cashiers see the hold but can't lift it" do
    sign_in_as users(:carl)
    get customer_path(@customer)
    assert_select "#credit-hold h2", "On hold"
    assert_select "#credit-hold form", count: 0
    post customer_credit_hold_lift_path(@customer), params: { days: "14", reason: "Please" }
    assert_response :forbidden
  end

  test "the till marks a held customer" do
    sign_in_as users(:carl)
    post pos_till_path, params: { register_id: registers(:acme_front).id }
    patch pos_customer_path, params: { customer_id: @customer.id }
    get pos_path
    assert_select ".badge", "On hold"
  end

  test "an owner sets credit control in Preferences" do
    sign_in_as users(:amina)
    get edit_preferences_path
    assert_select "#credit-control select[name='account[weekly_reminders]']"
    patch preferences_path, params: { account: { credit_hold_after_days: "45", weekly_reminders: "sms" } }
    assert_equal [ 45, "sms" ], in_acme { accounts(:acme).reload.then { [ _1.credit_hold_after_days, _1.weekly_reminders ] } }
  end
end
