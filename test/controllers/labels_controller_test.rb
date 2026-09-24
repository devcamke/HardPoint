require "test_helper"

class LabelsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:carl) }

  test "choose products and print" do
    get new_labels_path(query: "cement")
    assert_select "td", "Bamburi cement 50kg"

    get labels_path(copies: { products(:acme_cement).id => 3, products(:bolt_hammer).id => 2 }, format: "roll")
    assert_response :success
    assert_select ".label", 3, "another shop's product is ignored"
    assert_select ".roll svg.barcode[aria-label='Barcode 6161100420017']", 3
    assert_select ".price", /KES 800.00/
  end
end
