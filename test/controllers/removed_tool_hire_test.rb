require "test_helper"

# Tool hire was removed. What it left in the books stays usable: its orders, and its entries in the activity log.
class RemovedToolHireTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:amina) }

  test "an order from the old tool hire still opens, marked as such, and can't be edited" do
    order = Account.without_isolation do
      Current.set(account: accounts(:acme)) do
        accounts(:acme).customer_orders.create!(branch: branches(:acme_main), customer: customers(:acme_contractor), source: "hire", status: "ordered",
          lines_attributes: [ { account: accounts(:acme), product_code: "CEM-50", quantity: 1 } ])
      end
    end

    get customer_order_path(order)
    assert_response :success
    assert_select "p", /for a tool hire \(no longer in HardPoint\)/
    assert_not Account.without_isolation { order.reload.editable? }

    get customer_orders_path
    assert_select "td span.badge", "Hire"
  end

  test "activity entries about hire agreements and tools still read sensibly" do
    # As they sit in the database: their classes are gone, so they can't be built through Event.
    Account.without_isolation do
      Event.insert_all([
        { account_id: accounts(:acme).id, creator_id: users(:amina).id, eventable_type: "HireAgreement", eventable_id: 1, action: "created",
          particulars: { name: "MAIN-H00001", customer: "Peter Kamau" }, created_at: 1.hour.ago },
        { account_id: accounts(:acme).id, creator_id: users(:amina).id, eventable_type: "HireItem", eventable_id: 2, action: "updated",
          particulars: { name: "Concrete mixer" }, created_at: 1.hour.ago }
      ])
    end

    get events_path
    assert_response :success
    assert_select "p", /added hire agreement MAIN-H00001/
    assert_select "p", /changed hire item Concrete mixer/
  end

  test "its pages are gone" do
    get "/hire"
    assert_response :not_found
    get "/hire_terms/edit"
    assert_response :not_found
  end
end
