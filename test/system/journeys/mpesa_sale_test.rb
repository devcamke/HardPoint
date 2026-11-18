require "application_system_test_case"
require "net/http"

# A sale paid from the customer's phone: the cashier sends an M-Pesa prompt, the customer enters their PIN, and the
# till finishes the sale by itself. The shop's Paybill is on the simulator, and Safaricom's side is played by posting
# the callback it would send to the address it would send it to.
class MpesaSaleJourneyTest < ApplicationSystemTestCase
  journey "mpesa-sale"

  setup do
    @callback_token = Account.without_isolation do
      Current.set(account: accounts(:acme)) do
        accounts(:acme).mpesa_shortcodes.create!(name: "Paybill", shortcode: "174379", environment: "simulator").callback_token
      end
    end
  end

  test "a cashier sends an M-Pesa prompt and the sale completes when the customer pays" do
    step "Carl signs in and opens the Front counter till, where his shift is already open" do
      sign_in_with_browser users(:carl)
      click_on "Open a shift and start selling"
      click_on "Front counter"
      assert_text "25.5 kg here"
    end

    step "He weighs out four kilos of nails" do
      click_on "Wire nails 3 inch"
      within "dialog[open]" do
        fill_in "Quantity", with: "4"
        click_on "Add to sale"
      end
      within "#cart" do
        assert_text "Wire nails 3 inch"
        assert_text "Total KES 1,000.00", normalize_ws: true
      end
    end

    step "The customer wants to pay by M-Pesa, so he types their number" do
      within("#cart") { find("label", exact_text: "M-Pesa").click }
      fill_in "Send a prompt to pay KES 1,000.00 on Paybill 174379", with: "0722 000 111"
    end

    step "The prompt is on its way and the till waits" do
      click_on "Send prompt"
      assert_text "Prompt sent to 0722 000 111. Ask them to enter their M-Pesa PIN."
      assert_text "Waiting for 0722 000 111 to enter their M-Pesa PIN"
      assert_text "KES 1,000.00 on Paybill 174379. The sale completes by itself once they've paid."
    end

    step "The customer enters their PIN, and the till completes the sale without being touched" do
      safaricom_confirms_payment receipt: "SJK4H7T2QP"
      # The till asks every few seconds whether they've paid.
      assert_text "Sale MAIN-000001 complete · KES 1,000.00", wait: 15
      assert_text "M-Pesa SJK4H7T2QP received from 0722 000 111."
      within("#cart") { assert_text "Scan or tap products to start a sale." }
    end

    step "The sale records the M-Pesa code it was paid with" do
      click_link "Sales", exact: true
      click_on "MAIN-000001"
      assert_text "4 kg"
      assert_text "Mobile money · SJK4H7T2QP"
    end

    step "The shift report counts it as M-Pesa, not as cash in the drawer" do
      visit "/pos"
      click_link "Shift", exact: true
      assert_text "M-Pesa KES 1,000.00", normalize_ws: true
      assert_text "Cash sales KES 0.00", normalize_ws: true
      assert_text "Expected in drawer KES 5,000.00", normalize_ws: true
    end
  end

  private
    # What Safaricom does once the customer has entered their PIN: posts the result to the shop's callback address.
    # The prompt's details come from the simulator's queued stand-in for that call, and the post goes through the
    # server like any other request, so nothing here reaches into the database while the browser is using it.
    def safaricom_confirms_payment(receipt:)
      _shortcode, checkout_request_id, phone, amount = enqueued_jobs.reverse.find { _1[:job] == Mpesa::SimulatedCallbackJob }.fetch(:args)
      payload = Mpesa::SimulatedCallbackJob.payload(checkout_request_id, phone, amount)
      payload.dig("Body", "stkCallback", "CallbackMetadata", "Item").find { _1["Name"] == "MpesaReceiptNumber" }["Value"] = receipt

      response = Net::HTTP.post(URI("http://127.0.0.1:#{page.server.port}/webhooks/mpesa/#{@callback_token}/stk"), payload.to_json, "Content-Type" => "application/json")
      assert_equal "200", response.code, "Safaricom's callback was refused"
    end
end
