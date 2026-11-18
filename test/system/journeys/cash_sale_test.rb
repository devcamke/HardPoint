require "application_system_test_case"

# A cashier's whole day on one till, done the way a cashier does it: by clicking and typing in a browser. Every step
# checks what the cashier would see, and leaves a screenshot in tmp/journeys/cash-sale (kept by CI on every run).
class CashSaleJourneyTest < ApplicationSystemTestCase
  journey "cash-sale"

  test "a cashier opens a shift, sells for cash, and closes a balanced shift" do
    step "Carl signs in and lands on his home page" do
      sign_in_with_browser users(:carl)
      assert_text "Hi Carl"
    end

    step "He says which till this computer is" do
      click_on "Open a shift and start selling"
      assert_text "Which till is this?"
    end

    step "He counts the float and opens the shift" do
      click_on "Yard gate"
      assert_text "Open a shift on Yard gate"
      fill_in "Cash in the drawer to start (KES)", with: "2000"
      click_on "Open shift"
      assert_text "Shift open. Float KES 2,000.00."
      assert_text "10 bag here"
    end

    step "He taps cement, and the till asks how many" do
      click_on "Bamburi cement 50kg"
      within "dialog[open]" do
        assert_text "KES 800.00 each"
        fill_in "Quantity", with: "2"
      end
    end

    step "Two bags are on the sale" do
      within("dialog[open]") { click_on "Add to sale" }
      within "#cart" do
        assert_text "Bamburi cement 50kg"
        assert_text "Items 2"
        assert_text "Total KES 1,600.00", normalize_ws: true
      end
    end

    step "The customer hands over 2,000 and the till works out the change" do
      fill_in "Cash received", with: "2000"
      assert_text "Change: 400.00"
    end

    step "The sale is complete, with its receipt number and the change to give" do
      click_on "Take payment"
      within "#completed_sale" do
        assert_text "Sale YRD-000001 complete · KES 1,600.00"
        assert_text "Change KES 400.00"
      end
      assert_text "8 bag here"
      within("#cart") { assert_text "Scan or tap products to start a sale." }
    end

    step "The sale is in the day's sales" do
      click_link "Sales", exact: true
      assert_selector "h1", text: "Sales"
      assert_text "Carl Cashier"
      click_on "YRD-000001"
      assert_text "Timber yard · Yard gate · Carl Cashier"
      assert_text "2 bag"
      assert_text "Change given KES 400.00"
    end

    step "The receipt the customer takes away" do
      # The button opens the receipt in a new tab and prints it; here it's opened in this one, without the printing.
      visit find_link("Print receipt")[:href].sub(/\?.*/, "")
      assert_text "YRD-000001"
      assert_text "Bamburi cement 50kg"
      assert_text "1,600.00"
    end

    step "The shift so far: the float plus the cash sale" do
      visit "/pos"
      click_link "Shift", exact: true
      assert_text "X report (shift still open)"
      assert_text "Expected in drawer KES 3,600.00", normalize_ws: true
    end

    step "He counts the drawer and closes the shift" do
      click_on "Close shift"
      fill_in "Cash counted (KES)", with: "3600"
      accept_confirm("Close the shift? You won't be able to sell on this till until a new one is opened.") { click_on "Close shift" }
      assert_text "Shift closed."
      assert_text "Counted KES 3,600.00", normalize_ws: true
      assert_text "Balanced KES 0.00", normalize_ws: true
    end

    step "The till won't sell again until a new shift is opened" do
      click_on "Open till"
      assert_text "Open a shift on Yard gate"
    end
  end
end
