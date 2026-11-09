require "test_helper"

# A cashier bound to the timber yard sees nothing of the main branch: not its tills, sales, shifts or reports.
class BranchBoundStaffTest < ActionDispatch::IntegrationTest
  setup do
    @main_sale = Account.without_isolation do
      Current.set(account: accounts(:acme), session: accounts(:acme).sessions.create!(user: users(:carl))) do
        shifts(:acme_front_open).current_sale.tap { |sale| sale.add(products(:acme_nails)); sale.pay(tender: "card", reference: "VISA 1") }
      end
    end
    Account.without_isolation { memberships(:carl_acme).update!(branch: branches(:acme_yard)) }
    sign_in_as users(:carl)
  end

  test "only the yard's tills can be chosen, and a device set to a main till is treated as having none" do
    get new_pos_till_path
    assert_select "button, a, label", text: /Yard gate/
    assert_select "button, a, label", text: /Front counter/, count: 0

    post pos_till_path, params: { register_id: registers(:acme_front).id }
    assert_response :not_found

    post pos_till_path, params: { register_id: registers(:acme_yard).id }
    assert_redirected_to pos_path
  end

  test "the main branch's sales and shifts are out of sight" do
    get sales_path
    assert_response :success
    assert_select "a[href=?]", sale_path(@main_sale), count: 0

    get sale_path(@main_sale)
    assert_response :not_found

    get shift_path(shifts(:acme_front_open))
    assert_response :not_found
  end

  test "a cashier who isn't bound still can't open another till's shift report" do
    Account.without_isolation { memberships(:carl_acme).update!(branch: nil) }
    yard = Account.without_isolation { accounts(:acme).shifts.create!(branch: branches(:acme_yard), register: registers(:acme_yard), opened_by: users(:carl), opening_float_cents: 0, opened_at: Time.current) }
    post pos_till_path, params: { register_id: registers(:acme_yard).id }

    get shift_path(yard)
    assert_response :success
    get shift_path(shifts(:acme_front_open))
    assert_response :not_found, "another till's takings are a manager's business"
  end
end
