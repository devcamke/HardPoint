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

  test "search by phone" do
    sign_in_as users(:carl)
    get customers_path(query: "0722000111")
    assert_select "td a", "Mwangi Builders Ltd"
  end
end
