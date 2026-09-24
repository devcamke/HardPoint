require "test_helper"

class ProductImportTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:amina))
  end

  def import(csv, branch: branches(:acme_main))
    accounts(:acme).product_imports.create!(csv: csv, branch: branch, filename: "stock.csv").tap(&:check)
  end

  test "checks every row and reports problems by line" do
    result = import(<<~CSV)
      sku,name,price,unit,stock
      NEW-1,Hinge,150,Piece,10
      ,,abc,Parsec,1.5
      NEW-1,Duplicate,1,Piece,
    CSV

    assert result.needs_fixing?
    messages = result.problems.map { |problem| [ problem["line"], problem["messages"].to_sentence ] }
    assert_includes messages.to_h[3], "name is missing"
    assert_includes messages.to_h[3], "price “abc” isn't a number"
    assert_includes messages.to_h[3], "unit “Parsec” doesn't exist"
    assert messages.any? { _2.include?("SKUs used on more than one row: NEW-1") }
  end

  test "imports new products, updates existing ones, and sets stock through the ledger" do
    result = import(<<~CSV)
      sku,name,barcode,category,brand,unit,price,cost,tax_rate,reorder_level,stock
      CEM-50,Bamburi cement 50kg,,Building materials,Bamburi,Bag,850,700,Standard VAT,20,42
      TAP-1,Garden tap brass,5000000000017,Plumbing,Pegler,pc,1200,800,,3,6
      PAINT-W,White emulsion 4l,,Paint,,Piece,2100.50,1500,,2,
    CSV
    assert result.ready?, result.problems.inspect
    assert_equal [ 3, 2, 1 ], [ result.rows_count, result.created_count, result.updated_count ]

    result.update!(status: :importing)
    result.run

    assert result.reload.completed?
    cement = products(:acme_cement).reload
    assert_equal 85000, cement.price_cents
    assert_equal 42, cement.stock_at(branches(:acme_main))
    assert_equal "correction", cement.stock_movements.chronologically.first.reason

    tap = Product.find_by!(sku: "TAP-1")
    assert_equal [ "Plumbing", "Pegler", 6 ], [ tap.category.name, tap.brand.name, tap.stock_at(branches(:acme_main)) ]
    assert_equal [ "5000000000017" ], tap.barcodes.pluck(:code)
    assert_equal "opening", tap.stock_movements.sole.reason

    paint = Product.find_by!(sku: "PAINT-W")
    assert_equal 210050, paint.price_cents
    assert_match(/\A20\d{11}\z/, paint.barcodes.sole.code, "gets an in-store barcode")
    assert Category.exists?(name: "Paint")

    assert StockValuation.new(accounts(:acme)).reconciled?
  end

  test "columns missing from the file are left alone on existing products" do
    result = import("sku,name,price\nCEM-50,Bamburi cement 50kg,900\n")
    result.update!(status: :importing)
    result.run

    assert_equal categories(:acme_building), products(:acme_cement).reload.category
    assert_equal 90000, products(:acme_cement).price_cents
  end

  test "an import that would go past the plan's product allowance is held back" do
    accounts(:acme).update!(plan: "starter")
    csv = +"sku,name,price\n"
    2_001.times { |i| csv << "OVER-#{i},Item #{i},10\n" }
    result = import(csv)
    assert result.needs_fixing?
    assert_match "Starter plan allows 2,000 products in all", result.problems.flat_map { _1["messages"] }.join
  end

  test "barcodes already on another product are flagged" do
    result = import("sku,name,price,barcode\nNEW-2,Thing,1,6161100420017\n")
    assert result.needs_fixing?
  end

  test "20,000 rows import in a reasonable time" do
    accounts(:acme).update!(plan: "enterprise")
    csv = +"sku,name,category,unit,price,cost,stock\n"
    20_000.times { |i| csv << "BULK-#{i},Bulk item #{i},Bulk #{i % 50},Piece,#{100 + i % 900},#{50 + i % 400},#{i % 30}\n" }

    started = Time.current
    result = import(csv)
    assert result.ready?
    result.update!(status: :importing)
    result.run
    elapsed = Time.current - started

    assert_equal 20_000, Product.where("sku LIKE 'BULK-%'").count
    assert elapsed < 5.minutes, "took #{elapsed.round}s"
    puts "\n  20,000-row import: #{elapsed.round(1)}s" if ENV["VERBOSE"]
  end
end
