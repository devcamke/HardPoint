require "application_system_test_case"

# One document from first enquiry to goods handed over: a quote, the deposit that turns it into an order, and the
# collection at the till at the quoted price with the deposit taken off.
class QuoteToCollectionJourneyTest < ApplicationSystemTestCase
  journey "quote-to-collection"

  test "a quote becomes an order with a deposit and is collected at the till" do
    step "Carl signs in and opens the Front counter till, where his shift is already open" do
      sign_in_with_browser users(:carl)
      click_on "Open a shift and start selling"
      click_on "Front counter"
      assert_text "50 bag here"
    end

    step "A customer asks for a price, so he starts a quote" do
      click_on "Collect an order"
      assert_text "Nothing here yet."
      click_link "New", exact: true
      assert_text "New quote or order"
    end

    step "Five bags of cement for Grace Wambui" do
      select "Grace Wambui", from: "Customer"
      first("input[aria-label='Barcode or SKU']").set "CEM-50"
      first("input[aria-label='Quantity']").set "5"
    end

    step "The quote is saved at her price" do
      click_on "Save quote"
      assert_text "Quote MAIN-O00001 saved."
      assert_text "5 bag"
      assert_text "Total KES 4,000.00", normalize_ws: true
      assert_text "None taken. Taking a deposit confirms the quote."
    end
    order_page = current_url

    step "She pays KES 1,000 in cash to hold it" do
      click_on "Take deposit"
      assert_text "Cash goes into the drawer of Front counter."
      fill_in "Amount (KES)", with: "1000"
    end

    step "The deposit makes it an order, with the rest to pay on collection" do
      click_on "Take deposit"
      assert_text "Deposit of KES 1,000.00 recorded."
      assert_selector "h1", text: "Order MAIN-O00001"
      assert_text "Deposit held −KES 1,000.00", normalize_ws: true
      assert_text "To pay on collection KES 3,000.00", normalize_ws: true
    end

    step "The yard has it loaded, so it's marked ready" do
      click_on "Mark ready to collect"
      assert_text "Marked ready to collect."
    end

    step "She comes for it, and the order goes into the till at the quoted price" do
      click_on "Collect at Front counter"
      assert_text "MAIN-O00001 is in the till."
      within "#cart" do
        assert_text "Grace Wambui"
        assert_text "Order MAIN-O00001"
        assert_text "Total KES 4,000.00", normalize_ws: true
        assert_text "MAIN-O00001 has a KES 1,000.00 deposit to use."
      end
    end

    step "The deposit comes off first" do
      within("#cart") { find("label", exact_text: "Deposit").click }
      click_on "Take payment"
      assert_text "Deposit used KES 1,000.00 taken. KES 3,000.00 still due."
      within("#cart") { assert_text "Still due KES 3,000.00", normalize_ws: true }
    end

    step "She pays the rest in cash and the sale is complete" do
      fill_in "Cash received", with: "3000"
      click_on "Take payment"
      within("#completed_sale") { assert_text "Sale MAIN-000001 complete · KES 4,000.00" }
      assert_text "45 bag here"
    end

    step "Nothing is left waiting to be collected" do
      click_on "Collect an order"
      assert_text "Nothing here yet."
    end

    step "The order shows as collected, with the deposit used and the receipt it was sold on" do
      visit order_page
      assert_selector "h1", text: "Collected"
      assert_text "Used on collection KES 1,000.00", normalize_ws: true
      assert_link "MAIN-000001"
    end
  end
end
