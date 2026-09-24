require "test_helper"

class SmsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Account.without_isolation { accounts(:acme).update!(sms_enabled: true) }
    sign_in_as users(:amina)
  end

  test "texting a receipt, an order ready and a balance reminder" do
    sale, order = Account.without_isolation do
      Current.set(account: accounts(:acme), user: users(:carl)) do
        sale = shifts(:acme_front_open).current_sale
        sale.add(products(:acme_nails), quantity: 4)
        sale.change_customer(customers(:acme_contractor))
        sale.pay(tender: "on_account")
        order = accounts(:acme).customer_orders.create!(branch: branches(:acme_main), customer: customers(:acme_contractor), status: :ordered,
          lines_attributes: [ { account: accounts(:acme), product_code: "NAIL-3", quantity: 2 } ])
        [ sale, order ]
      end
    end

    perform_enqueued_jobs do
      post sale_receipt_text_path(sale), params: { phone: "0722 000 111" }
      assert_equal "Receipt texted to 0722 000 111.", flash[:notice]

      post customer_order_readiness_path(order), params: { notify: "1" }
      assert_match "has been sent a text", flash[:notice]

      post customer_balance_reminder_path(customers(:acme_contractor))
      assert_match "Reminder texted", flash[:notice]
    end

    assert_equal 3, Sms::Outbox.deliveries.size
    get sms_messages_path
    assert_select "td", "Order ready"
  end

  test "SMS turned off offers no texting" do
    Account.without_isolation { accounts(:acme).update!(sms_enabled: false) }
    get customer_path(customers(:acme_contractor))
    assert_select "button", text: "Text a reminder", count: 0
  end
end
