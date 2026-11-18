require "application_system_test_case"

# Goods coming back: a cashier can't refund by themselves. A manager types their PIN at the till, which approves
# this one return and signs nobody in.
class ReturnJourneyTest < ApplicationSystemTestCase
  journey "return"

  setup { Account.without_isolation { memberships(:amina_acme).set_approval_pin("2468") } }

  test "a cashier takes a bag back, and the refund goes through once a manager types their PIN" do
    step "Carl signs in and opens the Front counter till, where his shift is already open" do
      sign_in_with_browser users(:carl)
      click_on "Open a shift and start selling"
      click_on "Front counter"
      assert_text "50 bag here"
    end

    step "He sells three bags of cement for cash" do
      click_on "Bamburi cement 50kg"
      within "dialog[open]" do
        fill_in "Quantity", with: "3"
        click_on "Add to sale"
      end
      within("#cart") { assert_text "Total KES 2,400.00", normalize_ws: true }
      fill_in "Cash received", with: "2400"
      click_on "Take payment"
      within("#completed_sale") { assert_text "Sale MAIN-000001 complete · KES 2,400.00" }
      assert_text "47 bag here"
    end

    step "The customer brings one bag back, so he finds the sale" do
      click_link "Sales", exact: true
      click_on "MAIN-000001"
      click_on "Return items"
      assert_text "Return items from MAIN-000001"
      assert_text "Refunding at Front counter."
    end

    step "With the wrong PIN the return is refused" do
      find("input[aria-label='Returning Bamburi cement 50kg']").set "1"
      fill_in "Reason", with: "Bought one too many"
      fill_in "Manager approval PIN", with: "0000"
      click_on "Process return"
      assert_text "Returns need a manager's approval PIN."
      assert_text "Return items from MAIN-000001"
    end

    step "Amina comes over and types hers" do
      find("input[aria-label='Returning Bamburi cement 50kg']").set "1"
      fill_in "Reason", with: "Bought one too many"
      fill_in "Manager approval PIN", with: "2468"
    end

    step "KES 800 is refunded in cash, and the return names who approved it" do
      click_on "Process return"
      assert_text "Refund KES 800.00 by cash."
      assert_text "Return MAIN-R00001"
      assert_text "Carl Cashier · approved by Amina Owner · Bought one too many"
    end

    step "The sale shows what came back" do
      click_on "MAIN-000001"
      assert_text "Bamburi cement 50kg · 1 returned"
      assert_text "MAIN-R00001 −KES 800.00", normalize_ws: true
    end

    step "The bag is back on the shelf" do
      visit "/pos"
      assert_text "48 bag here"
    end

    step "The shift expects KES 800 less in the drawer" do
      click_link "Shift", exact: true
      assert_text "Cash sales KES 2,400.00", normalize_ws: true
      assert_text "Cash refunds −KES 800.00", normalize_ws: true
      assert_text "Expected in drawer KES 6,600.00", normalize_ws: true
    end
  end
end
