require "test_helper"

class Products::DetailsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:amina) }

  test "pack sizes, barcodes, prices and kit parts" do
    post product_units_path(products(:acme_pipe)), params: { product_unit: { unit_id: units(:acme_box).id, quantity: "10", price: "11000" } }
    post product_barcodes_path(products(:acme_pipe)), params: { barcode: { code: "6009876543210" } }
    post product_prices_path(products(:acme_pipe)), params: { price_list_item: { price_list_id: price_lists(:acme_contractor).id, min_quantity: "1", price: "1100" } }
    post product_components_path(products(:acme_plumbing_kit)), params: { kit_component: { product_code: "NAIL-3", quantity: "0.5" } }

    Account.without_isolation do
      pipe = products(:acme_pipe).reload
      assert_equal 1, pipe.product_units.count
      assert_includes pipe.barcodes.pluck(:code), "6009876543210"
      assert_equal 110000, pipe.price_cents_for(price_list: price_lists(:acme_contractor))
      assert_includes products(:acme_plumbing_kit).components, products(:acme_nails)
    end
  end

  test "problems come back as a message" do
    post product_barcodes_path(products(:acme_pipe)), params: { barcode: { code: "6161100420017" } }
    follow_redirect!
    assert_select "#alert", /already used by another product/

    post product_components_path(products(:acme_plumbing_kit)), params: { kit_component: { product_code: "HAM-16", quantity: "1" } }
    follow_redirect!
    assert_select "#alert", /No product with barcode or SKU/
  end

  test "another shop's product is out of reach" do
    post product_barcodes_path(products(:bolt_hammer)), params: { barcode: { code: "1" } }
    assert_response :not_found
  end
end
