require "test_helper"

class MaterialEstimatesControllerTest < ActionDispatch::IntegrationTest
  def acme(&) = Account.without_isolation(&)

  setup do
    acme { accounts(:acme).material_products.create!(material: "cement", product: products(:acme_cement)) }
    @customer = acme { customers(:acme_contractor) }
  end

  test "adding parts, working them out, and making a quote" do
    sign_in_as users(:carl)
    get new_material_estimate_path
    assert_select "h2", "Wall"

    post material_estimate_path, params: { add: "concrete", parts: { "0" => { kind: "wall" } } }
    assert_select "h2", "Concrete"
    assert_select "input[name='parts[1][kind]'][value=concrete]"

    parts = { "0" => { kind: "wall" }, "1" => { kind: "concrete", length: "5", width: "4", thickness: "0.15", mix: "1:2:4", steel: "none" } }
    post material_estimate_path, params: { parts: parts }
    assert_select "aside li", /Cement/
    assert_select "aside li", /Ballast.*not linked to a product/m

    post material_estimate_path, params: { parts: parts, remove: "0" }
    assert_select "h2", text: "Wall", count: 0

    post material_estimate_path, params: { parts: parts, make_quote: "1" }
    assert_response :unprocessable_entity
    assert_match "Choose the customer", response.body

    assert_difference -> { acme { CustomerOrder.count } } do
      post material_estimate_path, params: { parts: parts, make_quote: "1", customer_id: @customer.id }
    end
    quote = acme { CustomerOrder.order(:id).last }
    assert_redirected_to customer_order_path(quote)
    acme do
      assert quote.quote?
      assert_equal [ products(:acme_cement) ], quote.lines.map(&:product), "only linked materials go on the quote"
      assert_equal (3 * 1.54 * 1.05 / 7 * 1440 / 50).ceil, quote.lines.sole.quantity
    end
  end

  test "linking materials to products, by SKU, with a conversion" do
    sign_in_as users(:amina)
    get edit_material_products_path
    assert_select "input[name='materials[sand][product_code]']"

    patch material_products_path, params: { materials: { cement: { product_code: "", factor: "1" }, sand: { product_code: "NAIL-3", factor: "1000" } } }
    assert_redirected_to new_material_estimate_path
    acme do
      assert_nil accounts(:acme).material_products.find_by(material: "cement"), "a cleared product unlinks the material"
      sand = accounts(:acme).material_products.find_by!(material: "sand")
      assert_equal [ products(:acme_nails), 1000 ], [ sand.product, sand.factor ]
    end

    patch material_products_path, params: { materials: { sand: { product_code: "NOPE-1", factor: "1" } } }
    assert_response :unprocessable_entity
    assert_match "No product with SKU, barcode or name “NOPE-1”", response.body
  end

  test "linking materials is for whoever looks after the catalogue" do
    sign_in_as users(:carl)
    get edit_material_products_path
    assert_response :forbidden
  end
end
