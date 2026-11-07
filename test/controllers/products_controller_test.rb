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

  test "the search bar shows active filters as facets that can be removed" do
    plumbing = categories(:acme_plumbing)
    get products_path(category_id: plumbing.id, query: "pvc")

    assert_select "form[role=search]" do
      assert_select "span", text: "Category: Plumbing"
      assert_select "span", text: "Search: pvc"
      assert_select "a[aria-label='Remove Category: Plumbing'][href=?]", products_path(query: "pvc")
      assert_select "a[aria-label='Remove Search: pvc'][href=?]", products_path(category_id: plumbing.id)
      assert_select "a[aria-current=true]", text: /Plumbing/
    end
    assert_select "td a", "PVC pipe 2 inch 6m"
  end

  test "grouping by category counts the whole list and opens each group on demand" do
    plumbing = categories(:acme_plumbing)
    get products_path(group_by: "category")

    assert_select "details summary", text: /Fasteners\s*\(2\)/
    assert_select "details summary", text: /Plumbing\s*\(2\)/
    assert_select "td a", count: 0, message: "records load when a group is opened"
    assert_select "turbo-frame#group_#{plumbing.id}[loading=lazy][target=_top][src*='category_id=#{plumbing.id}']"
    assert_select "form[role=search] span", text: "Group by: Category"

    get products_path(category_id: plumbing.id, frame: "group_#{plumbing.id}")
    assert_select "turbo-frame#group_#{plumbing.id}" do
      assert_select "td a", "PVC pipe 2 inch 6m"
      assert_select "td a", text: "Bamburi cement 50kg", count: 0
    end
  end

  test "grouping by brand puts products without one under No brand, which filters to them" do
    get products_path(group_by: "brand")
    assert_select "details summary", text: /Bamburi\s*\(1\)/
    assert_select "details summary", text: /No brand\s*\(4\)/

    get products_path(brand_id: "none")
    assert_select "td a", "PVC pipe 2 inch 6m"
    assert_select "td a", text: "Bamburi cement 50kg", count: 0
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

  test "the form asks for the everyday fields and keeps the rest under More options" do
    get new_product_path
    assert_select "form > .card > .field input[name='product[name]']"
    assert_select "input[name='product[opening_stock]']"
    assert_select "details summary", /More options\s+SKU made for you · tax: Standard VAT/
    assert_select "details input[name='product[sku]']"
    assert_select "details select[name='product[tax_rate_id]']"
  end

  test "opening stock is recorded at the branch through the stock ledger" do
    post products_path, params: { branch_id: branches(:acme_main).id,
      product: { name: "Door hinge 4 inch", unit_id: units(:acme_piece).id, price: "150", opening_stock: "40" } }

    product = Account.without_isolation { Product.find_by!(name: "Door hinge 4 inch") }
    assert_redirected_to product_path(product)
    assert_equal 40, Account.without_isolation { product.stock_at(branches(:acme_main)) }
    assert_equal [ "opening" ], Account.without_isolation { product.stock_movements.pluck(:reason) }
  end

  test "opening stock that doesn't fit the unit saves nothing" do
    assert_no_difference -> { Account.without_isolation { Product.count } } do
      post products_path, params: { product: { name: "Door hinge 4 inch", unit_id: units(:acme_piece).id, price: "150", opening_stock: "2.5" } }
    end
    assert_response :unprocessable_entity
    assert_select "#error_explanation", /Opening stock must be a whole number/
  end

  test "add and start another keeps the category and unit" do
    post products_path, params: { add_another: "Add and start another",
      product: { name: "Door hinge 4 inch", unit_id: units(:acme_piece).id, category_id: categories(:acme_fasteners).id, price: "150" } }

    assert_redirected_to new_product_path(category_id: categories(:acme_fasteners).id, unit_id: units(:acme_piece).id)
    follow_redirect!
    assert_select "select[name='product[category_id]'] option[selected][value='#{categories(:acme_fasteners).id}']"
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
