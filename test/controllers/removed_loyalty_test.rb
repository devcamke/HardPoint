require "test_helper"

# Loyalty points and the customer display were removed. Sales paid partly with points before then
# keep their payments, receipts, reports and eTIMS code.
class RemovedLoyaltyTest < ActionDispatch::IntegrationTest
  setup do
    @sale = Account.without_isolation do
      Current.set(account: accounts(:acme), user: users(:carl)) do
        shifts(:acme_front_open).current_sale.tap do |sale|
          sale.add(products(:acme_nails))
          # As a points payment taken before the removal sits in the database.
          Payment.create!(account: accounts(:acme), sale: sale, tender: "points", amount_cents: 100_00, points: 100)
          sale.pay(tender: "cash")
        end
      end
    end
    sign_in_as users(:amina)
  end

  test "a sale paid partly with points still shows the points on its page, receipt and the payments report" do
    assert Account.without_isolation { @sale.reload.completed? }

    get sale_path(@sale)
    assert_response :success
    assert_match "100 points", response.body

    get sale_receipt_path(@sale)
    assert_match "100 points", response.body

    get report_path("payments", preset: "today")
    assert_select "th", "Points"
  end

  test "points payments keep their eTIMS payment type" do
    assert_equal "07", Etims::PAYMENT_TYPES.fetch("points")
  end

  test "the till no longer offers points, and the loyalty and display pages are gone" do
    assert_not_includes Account::Features::KEYS, "loyalty"

    get "/loyalty/edit"
    assert_response :not_found
    get "/pos/display"
    assert_response :not_found
  end
end
