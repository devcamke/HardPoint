require "application_system_test_case"

# A shop that didn't exist this morning: signed up on the public site, signed in on its own address, and selling
# its first product from its first till.
class SignUpJourneyTest < ApplicationSystemTestCase
  journey "sign-up"

  test "a new shop signs up, adds a product and a till, and makes its first sale" do
    step "Wanjiru finds HardPoint and presses the button to start" do
      visit_public "/"
      first(:link, "Start now, it's free").click
      assert_text "Open your shop"
    end

    step "She names her shop and picks its web address" do
      fill_in "Business name", with: "Juja Hardware"
      fill_in "Web address", with: "juja"
      fill_in "Your name", with: "Wanjiru Kamau"
      fill_in "Email address", with: "wanjiru@juja.test"
      fill_in "Password", with: "nails-and-cement-42"
      find("input[type=checkbox][name='signup[terms_accepted]']").check
    end

    step "The shop exists, at its own address, and asks her to sign in" do
      click_on "Create my shop"
      assert_text "Sign in to Juja Hardware"
      assert_equal "juja.localhost", URI(current_url).host
      assert_field "Email address", with: "wanjiru@juja.test"
    end

    step "She signs in to an empty shop with a setup list" do
      fill_in "Password", with: "nails-and-cement-42"
      click_on "Sign in"
      assert_text "Set up your shop: 0 of 4 done"
      assert_text "No tills open"
    end

    step "Her first product, with what's on the shelf" do
      click_on "New product"
      assert_selector "h1", text: "New product"
      fill_in "Name", with: "Simba cement 50kg"
      fill_in "Selling price (KES)", with: "750"
      fill_in "Cost price (KES)", with: "690"
      select "Bag", from: "Sold by"
      fill_in "Opening stock at Main branch", with: "40"
      click_on "Add product"
      assert_text "Simba cement 50kg added with 40 bag at Main branch."
    end

    step "There's no till yet, and the till says where to add one" do
      click_on "Open till"
      assert_text "This shop has no tills yet."
      click_on "Add one in Settings"
      click_on "Add till"
      assert_selector "h1", text: "New till"
      fill_in "Name", with: "Counter 1"
    end

    step "Her first till" do
      click_on "Create Till"
      assert_text "Till added."
      assert_text "Counter 1 Main branch", normalize_ws: true
    end

    step "She opens a shift on it, and her cement is there to sell" do
      click_on "Open till"
      click_on "Counter 1"
      assert_text "Open a shift on Counter 1"
      fill_in "Cash in the drawer to start (KES)", with: "1000"
      click_on "Open shift"
      assert_text "Shift open. Float KES 1,000.00."
      assert_text "40 bag here"
    end

    step "The shop's first sale" do
      click_on "Simba cement 50kg"
      within("dialog[open]") { click_on "Add to sale" }
      within("#cart") { assert_text "Total KES 750.00", normalize_ws: true }
      fill_in "Cash received", with: "1000"
      click_on "Take payment"
      within "#completed_sale" do
        assert_text "Sale MAI-000001 complete · KES 750.00"
        assert_text "Change KES 250.00"
      end
      assert_text "39 bag here"
    end
  end
end
