require "application_system_test_case"

# A customer who buys on account sees what they owe on their own page and pays some of it from their phone. The
# owner and the customer are two people at two browsers; Safaricom's side is played as in the M-Pesa sale journey.
class CustomerPortalJourneyTest < ApplicationSystemTestCase
  journey "customer-portal"

  setup do
    Account.without_isolation { accounts(:acme).update!(features: accounts(:acme).features | [ "customer_portal" ]) }
    @callback_token = connect_simulated_paybill
  end

  test "a contractor buys on account, opens their portal link and pays part of it by M-Pesa" do
    step "Amina signs in and opens the Front counter till" do
      sign_in_with_browser users(:amina)
      click_on "Open till"
      click_on "Front counter"
      assert_text "3 pc here"
    end

    step "The sale is for Mwangi Builders, who buy on account" do
      within "#cart" do
        find("summary", exact_text: "Change").click
        find("input[aria-label='Find customer']").set "Mwangi"
        click_on "Mwangi Builders Ltd"
      end
      within("#cart") { assert_text "Mwangi Builders Ltd Contractor", normalize_ws: true }
    end

    step "Two lengths of pipe go on their account" do
      click_on "PVC pipe 2 inch 6m"
      within "dialog[open]" do
        fill_in "Quantity", with: "2"
        click_on "Add to sale"
      end
      within "#cart" do
        assert_text "Total KES 2,400.00", normalize_ws: true
        find("label", exact_text: "Account").click
      end
      click_on "Take payment"
      within("#completed_sale") { assert_text "Sale MAIN-000001 complete · KES 2,400.00" }
    end

    step "Their account shows the invoice, and she makes them a link to their own page" do
      visit "/customers"
      click_on "Mwangi Builders Ltd"
      assert_text "Owes on account KES 2,400.00", normalize_ws: true
      click_on "Make a link"
      assert_text "The customer's portal link is ready to copy."
    end
    portal_page = URI(find("input[aria-label='Portal link']").value).path

    using_session :customer do
      step "The customer opens the link on their phone, without signing in to anything" do
        visit portal_page
        assert_text "Account of Mwangi Builders Ltd"
        assert_text "You owe KES 2,400.00", normalize_ws: true
        assert_text "MAIN-000001"
      end

      step "They choose to pay KES 1,500 of it now" do
        assert_field "Safaricom number", with: "0722 000 111"
        fill_in "Amount (KES)", with: "1500"
      end

      step "A prompt goes to their phone and the page waits" do
        click_on "Send the M-Pesa prompt"
        assert_text "Check your phone"
        assert_text "We've sent an M-Pesa prompt for KES 1,500.00 to 0722 000 111."
      end

      step "They enter their PIN, and the page says thank you by itself" do
        safaricom_confirms_payment @callback_token, receipt: "SJK4H7T2QP"
        # The page looks again every few seconds.
        assert_text "Paid, thank you", wait: 15
        assert_text "KES 1,500.00 received, M-Pesa SJK4H7T2QP. It's on your account."
      end

      step "Their page now shows KES 900 left on that invoice, and the payment" do
        click_on "Back to your account"
        assert_text "You owe KES 900.00", normalize_ws: true
        assert_text "KES 900.00 of KES 2,400.00", normalize_ws: true
        assert_text "Mobile money · SJK4H7T2QP"
      end
    end

    step "Back in the shop, the account has come down by what they paid" do
      page.refresh
      assert_text "Owes on account KES 900.00", normalize_ws: true
      assert_text "SJK4H7T2QP"
    end
  end
end
