require "test_helper"

class WhatsappMessagesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def acme(&) = Account.without_isolation(&)

  setup do
    acme do
      customers(:acme_contractor).update_columns(phone: "0722000111")
      Current.set(account: accounts(:acme), session: accounts(:acme).sessions.create!(user: users(:amina))) do
        stock_up products(:acme_nails), 10
        @sale = shifts(:acme_front_open).current_sale
        @sale.change_customer(customers(:acme_contractor))
        @sale.add(products(:acme_nails), quantity: 4)
        @sale.pay(tender: "on_account", credit_approver: users(:amina))
      end
    end
    @customer = acme { customers(:acme_contractor) }
  end

  test "a receipt is sent from the share menu and its page shows it went, in test mode" do
    sign_in_as users(:carl)
    get sale_path(@sale)
    assert_select "form[action='#{whatsapp_messages_path}'] button", /Send on WhatsApp/

    perform_enqueued_jobs { post whatsapp_messages_path, params: { kind: "receipt", id: @sale.id, phone: "0722000111" } }
    assert_match "Sending on WhatsApp", flash[:notice]
    get sale_path(@sale)
    assert_select "section", /Sent on WhatsApp.*Test mode/m
  end

  test "a balance reminder is for those who look after accounts, and the feature must be on" do
    sign_in_as users(:carl)
    post whatsapp_messages_path, params: { kind: "statement", id: @customer.id, reminder: 1 }
    assert_response :not_found, "a cashier can't hand out a customer's statement"

    sign_in_as users(:amina)
    get customer_path(@customer)
    assert_select "form[action='#{whatsapp_messages_path}'] button", "Remind on WhatsApp"
    perform_enqueued_jobs { post whatsapp_messages_path, params: { kind: "statement", id: @customer.id, reminder: 1 } }
    assert_equal "hardpoint_balance_reminder", acme { Whatsapp::Message.last.template }
    get whatsapp_messages_path
    assert_select "td", /Balance reminder/
    assert_match "Test mode.", response.body

    acme { accounts(:acme).update_columns(features: Account::Features::KEYS - [ "whatsapp_messages" ]) }
    post whatsapp_messages_path, params: { kind: "receipt", id: @sale.id, phone: "0722000111" }
    assert_response :not_found
  end
end
