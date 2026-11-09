require "test_helper"

class CustomersControllerTest < ActionDispatch::IntegrationTest
  test "cashiers add customers but can't grant credit or special prices" do
    sign_in_as users(:carl)
    post customers_path, params: { customer: { name: "Otieno Fundi", phone: "0711 222 333", credit_limit: "100000", price_list_id: price_lists(:acme_contractor).id } }

    customer = Account.without_isolation { Customer.find_by!(name: "Otieno Fundi") }
    assert_equal [ "0711222333", 0, nil ], [ customer.phone, customer.credit_limit_cents, customer.price_list_id ]
  end

  test "managers can" do
    sign_in_as users(:amina)
    patch customer_path(customers(:acme_walk_in)), params: { customer: { credit_limit: "20000", price_list_id: price_lists(:acme_contractor).id } }
    assert_equal 2000000, Account.without_isolation { customers(:acme_walk_in).reload.credit_limit_cents }
  end

  test "a customer can ask not to be texted, and then isn't offered a reminder" do
    sign_in_as users(:amina)
    Account.without_isolation { accounts(:acme).update!(sms_enabled: true) }
    customer = customers(:acme_contractor)

    get edit_customer_path(customer)
    assert_select "input[name='customer[sms_opt_out]'][type=checkbox]"
    patch customer_path(customer), params: { customer: { sms_opt_out: "1" } }
    assert Account.without_isolation { customer.reload.sms_opt_out? }

    Account.without_isolation do
      Current.set(account: accounts(:acme), user: users(:carl)) do
        sale = shifts(:acme_front_open).current_sale
        sale.change_customer(customer)
        sale.add(products(:acme_nails), quantity: 4)
        sale.pay(tender: "on_account")
      end
    end
    get customer_path(customer)
    assert_select "button", text: "Text a reminder", count: 0
    assert_select "p", /asked not to be texted/
  end

  test "search by phone" do
    sign_in_as users(:carl)
    get customers_path(query: "0722000111")
    assert_select "td a", "Mwangi Builders Ltd"
  end
end
