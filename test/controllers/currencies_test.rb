require "test_helper"

class CurrenciesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:acme)
  end

  def acme(&) = Account.without_isolation(&)

  test "owners set rates; the till takes dollars and the drawer counts them apart" do
    sign_in_as users(:amina), account: @account
    post currencies_path, params: { currency: { code: "usd", rate: "129.50", accepted_at_till: "1" } }
    usd = acme { @account.currencies.find_by!(code: "USD") }
    assert_redirected_to currencies_path
    patch currency_path(usd), params: { currency: { rate: "130" } }
    assert_equal 130, acme { usd.reload.rate }
    get currencies_path
    assert_select "##{dom_id(usd)}", /1 KES = 0.0077 USD/

    post pos_till_path, params: { register_id: registers(:acme_front).id }
    post pos_lines_path, params: { code: "CEM-50" }, as: :turbo_stream
    assert_select "input[name=tender][value=foreign_cash]"
    post pos_payments_path, params: { tender: "foreign_cash", currency: "USD", foreign_tendered: "10" }
    sale = acme { @account.sales.completed.last }
    payment = acme { sale.payments.sole }
    assert_equal [ 1300_00, 500_00 ], [ payment.tendered_cents, payment.change_cents ]
    get sale_receipt_path(sale)
    assert_match "USD 10.00 cash @ 130", response.body

    shift = acme { shifts(:acme_front_open) }
    get new_shift_closing_path(shift)
    assert_select "input[name='counted_foreign[USD]']"
    post shift_closing_path(shift), params: { counted_cash: "4500", counted_foreign: { "USD" => "10" } }
    assert_equal({ "USD" => { "expected" => 10_00, "counted" => 10_00 } }, acme { shift.reload.foreign_cash })
    get shift_path(shift)
    assert_select "div", /Expected USD/
  end

  test "cashiers see rates but can't change them" do
    usd = acme { Current.set(account: @account) { @account.currencies.create!(code: "USD", rate: 129.5) } }
    sign_in_as users(:carl), account: @account
    get currencies_path
    assert_response :success
    patch currency_path(usd), params: { currency: { rate: "1" } }
    assert_response :forbidden
  end
end
