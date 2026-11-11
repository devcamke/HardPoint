require "test_helper"

class StockReservationsTest < ActionDispatch::IntegrationTest
  test "an owner chooses to hold order stock, and the product page shows what's held and for which order" do
    sign_in_as users(:amina)
    order = Account.without_isolation do
      Current.set(account: accounts(:acme), user: users(:amina)) do
        accounts(:acme).customer_orders.create!(branch: branches(:acme_main), customer: customers(:acme_contractor),
          lines_attributes: [ { account: accounts(:acme), product_code: "CEM-50", quantity: 30 } ]).tap { _1.confirm(approver: users(:amina)) }
      end
    end

    patch preferences_path, params: { account: { order_stock: "hold" } }
    assert Account.without_isolation { accounts(:acme).reload.hold_order_stock? }

    get product_path(products(:acme_cement))
    assert_select "td span", /30 held for/
    assert_select "td span a[href=?]", customer_order_path(order), text: order.reference
  end
end
