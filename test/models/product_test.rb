require "test_helper"

class ProductTest < ActiveSupport::TestCase
  setup { Current.account = accounts(:acme) }

  test "prices are entered as amounts and stored as cents" do
    product = accounts(:acme).products.new(name: "Hinge", unit: units(:acme_piece), price: "1,250.50", cost: "900")

    assert_equal 125050, product.price_cents
    assert_equal BigDecimal("1250.5"), product.price
    assert_equal 90000, product.cost_cents
  end

  test "SKUs are unique within a shop, normalized, and generated when left blank" do
    duplicate = accounts(:acme).products.new(name: "Copy", sku: " cem-50 ", unit: units(:acme_piece), price: 1)
    assert_not duplicate.valid?
    assert_equal "CEM-50", duplicate.sku

    generated = accounts(:acme).products.create!(name: "Hinge", unit: units(:acme_piece), price: 1)
    assert_match(/\AP[A-Z0-9]{7}\z/, generated.sku)
  end

  test "another shop can use the same SKU" do
    Current.account = accounts(:bolt)
    assert accounts(:bolt).products.create!(name: "Cement", sku: "CEM-50", unit: units(:bolt_piece), price: 1)
  end

  test "references must belong to the same shop" do
    product = accounts(:acme).products.new(name: "Mixed", unit: units(:acme_piece), price: 1, category_id: categories(:bolt_tools).id)

    assert_not product.valid?
    assert_includes product.errors[:category], "must belong to this shop"
  end

  test "new products without a barcode get an in-store EAN-13" do
    product = accounts(:acme).products.create!(name: "Hinge", unit: units(:acme_piece), price: 1)

    code = product.barcodes.sole.code
    assert_match(/\A20\d{11}\z/, code)
    assert product.barcodes.sole.ean13?
  end

  test "labels prefer the manufacturer's barcode" do
    product = accounts(:acme).products.create!(name: "Hinge", unit: units(:acme_piece), price: 1)
    product.barcodes.create!(account: accounts(:acme), code: "5012345678900")

    assert_equal "5012345678900", product.reload.primary_barcode
  end

  test "a branch only reorders what it carries" do
    low_at_yard = Product.below_reorder_level_at(branches(:acme_yard))
    assert_includes low_at_yard, products(:acme_cement), "carried, 10 of 20"
    assert_not_includes low_at_yard, products(:acme_pipe), "never stocked at the yard"

    brand_new = accounts(:acme).products.create!(name: "New tile", unit: units(:acme_piece), price: 1, reorder_level: 5)
    assert_includes low_at_yard.reload, brand_new, "never stocked anywhere yet"
  end

  test "the best applicable price wins" do
    cement = products(:acme_cement)

    assert_equal 80000, cement.price_cents_for(quantity: 1)
    assert_equal 77000, cement.price_cents_for(quantity: 50), "retail quantity break"
    assert_equal 76000, cement.price_cents_for(quantity: 1, price_list: price_lists(:acme_contractor))
  end

  test "pack sizes are priced on their own or from their pieces" do
    box = product_units(:acme_screws_box)
    assert_equal 40000, box.effective_price_cents

    box.price_cents = nil
    assert_equal 50000, box.effective_price_cents
  end

  test "kits are in stock as often as their scarcest component allows" do
    # 3 pipes / 2 per kit = 1; 1000 screws / 20 = 50
    assert_equal 1, products(:acme_plumbing_kit).stock_at(branches(:acme_main))
    assert_equal 0, products(:acme_plumbing_kit).stock_at(branches(:acme_yard))
  end

  test "kits can't contain kits" do
    component = products(:acme_plumbing_kit).kit_components.new(component: products(:acme_plumbing_kit), quantity: 1)
    assert_not component.valid?
  end

  test "search matches every word in the name or SKU, and exact barcodes" do
    assert_equal [ products(:acme_pipe) ], Product.search("pvc 2 inch").to_a
    assert_equal [ products(:acme_cement) ], Product.search("6161100420017").to_a
    assert_equal products(:acme_screws), Product.search("scr-815").first
    assert_empty Product.search("hammer"), "another shop's products never match"
  end

  test "find by code accepts pack barcodes and SKUs" do
    assert_equal products(:acme_screws), Product.find_by_code("6001234500012")
    assert_equal products(:acme_cement), Product.find_by_code("cem-50")
    assert_nil Product.find_by_code("0076174512345")
  end
end
