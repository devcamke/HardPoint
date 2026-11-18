require "application_system_test_case"

# Stock coming in: an order to a supplier, a delivery that arrives short, and the shelf count that follows.
class PurchasingJourneyTest < ApplicationSystemTestCase
  journey "purchasing"

  test "a stock clerk orders cement, receives a short delivery, and the stock goes up by what arrived" do
    step "Sara the stock clerk signs in" do
      sign_in_with_browser users(:sara)
      assert_text "Hi Sara"
    end

    step "Cement is running down, so she starts an order to the distributor" do
      within("nav[aria-label='Main']") { click_link "Buy", exact: true }
      assert_text "No purchase orders."
      click_link "New", exact: true
      assert_text "New purchase order"
      select "Nairobi Cement Distributors", from: "Supplier"
      first("input[aria-label='Barcode or SKU']").set "CEM-50"
      first("input[aria-label='Quantity']").set "20"
    end

    step "The draft is priced at what the distributor charges" do
      click_on "Save draft"
      assert_text "Draft MAIN-PO00001 saved. Check it, then send it to Nairobi Cement Distributors."
      assert_text "20 bag 0 20 KES 680.00 KES 13,600.00", normalize_ws: true
    end

    step "She phones it in and marks it sent" do
      click_on "Mark sent (phoned in)"
      assert_text "Marked as sent."
    end

    step "The lorry comes two bags short, and she counts what's there" do
      click_on "Receive goods"
      assert_text "Receive goods for MAIN-PO00001"
      fill_in "Delivery note number", with: "DN-4471"
      find("input[aria-label='Quantity received']").set "18"
    end

    step "Eighteen bags go into stock" do
      click_on "Receive into stock"
      assert_text "Received into Main branch. Stock and costs are updated."
      assert_text "delivery note DN-4471 · for MAIN-PO00001"
      assert_text "Bamburi cement 50kg 18 bag KES 680.00", normalize_ws: true
    end

    step "The order shows two still to come" do
      click_on "MAIN-PO00001"
      assert_text "Partially received"
      assert_text "20 bag 18 2 KES 680.00", normalize_ws: true
      assert_button "Close short"
    end

    step "The product has 68 bags at the branch, and its history says where 18 came from" do
      click_on "Bamburi cement 50kg"
      assert_text "Main branch 68 bag", normalize_ws: true
      assert_text "Main branch Received +18 68 Sara Stockclerk", normalize_ws: true
    end
  end
end
