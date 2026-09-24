require "test_helper"

class ProductsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:amina) }

  test "index lists and searches this shop's products with stock at the chosen branch" do
    get products_path(branch_id: branches(:acme_main).id)
    assert_response :success
    assert_select "td a", "Bamburi cement 50kg"
    assert_select "td a", text: "Claw hammer 16oz", count: 0

    get products_path(query: "pvc inch")
    assert_select "tbody tr", 1
    assert_select "td a", "PVC pipe 2 inch 6m"
  end

  test "a scanned barcode finds its product" do
    get products_path(query: "6161100420017")
    assert_select "tbody tr", 1
  end

  test "creating a product with a manufacturer's barcode" do
    post products_path, params: { product: { name: "Door hinge 4 inch", unit_id: units(:acme_piece).id, price: "150", cost: "90", barcode: "5012345678900" } }

    product = Account.without_isolation { Product.find_by!(name: "Door hinge 4 inch") }
    assert_redirected_to product_path(product)
    assert_equal [ "5012345678900" ], Account.without_isolation { product.barcodes.pluck(:code) }
  end

  test "a taken barcode is rejected and nothing is saved" do
    assert_no_difference -> { Account.without_isolation { Product.count } } do
      post products_path, params: { product: { name: "Copycat", unit_id: units(:acme_piece).id, price: "1", barcode: "6161100420017" } }
    end
    assert_response :unprocessable_entity
  end

  test "another shop's category can't be used" do
    patch product_path(products(:acme_screws)), params: { product: { category_id: categories(:bolt_tools).id } }

    assert_response :unprocessable_entity
    assert_equal categories(:acme_fasteners).id, Account.without_isolation { products(:acme_screws).reload.category_id }
  end

  test "another shop's products can't be reached" do
    get product_path(products(:bolt_hammer))
    assert_response :not_found
  end

  test "products with stock history can't be deleted" do
    delete product_path(products(:acme_cement))
    assert_redirected_to product_path(products(:acme_cement))
    assert Account.without_isolation { Product.exists?(products(:acme_cement).id) }
  end

  test "export is a CSV that import understands" do
    get products_path(format: :csv, branch_id: branches(:acme_main).id)

    assert_response :success
    rows = CSV.parse(response.body, headers: true)
    assert_equal ProductCsv::HEADERS, rows.headers
    cement = rows.find { _1["sku"] == "CEM-50" }
    assert_equal [ "800.00", "700.00", "50", "6161100420017" ], cement.values_at("price", "cost", "stock", "barcode")
  end

  test "cashiers can browse but not edit, and don't see costs" do
    sign_in_as users(:carl)

    get product_path(products(:acme_cement))
    assert_response :success
    assert_select "p", text: "Cost", count: 0

    get edit_product_path(products(:acme_cement))
    assert_response :forbidden

    get products_path(format: :csv)
    assert_nil CSV.parse(response.body, headers: true).first["cost"]
  end
end
