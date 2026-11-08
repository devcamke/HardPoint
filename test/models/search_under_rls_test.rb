require "test_helper"

# Searches match through SQL functions that row-level security doesn't apply to (SearchFunctions), so Postgres
# can use the trigram indexes; the functions take the shop's id and can only return that shop's rows.
class SearchUnderRlsTest < ActiveSupport::TestCase
  setup { Current.account = accounts(:acme) }

  test "the search functions belong to the role that bypasses row-level security" do
    assert SearchFunctions.role_exists?, "create the #{SearchFunctions::ROLE} role (README)"
    assert SearchFunctions.bypassing_rls?, "run bin/rails db:search:privileges"
  end

  test "products, customers and suppliers search as before, within the shop only" do
    assert_equal [ "Wire nails 3 inch" ], Product.search("nail").map(&:name)
    assert_equal [ "PVC pipe 2 inch 6m" ], Product.search("pvc 2 inch").map(&:name)
    assert_equal [ "Wood screws 8x1.5" ], Product.search("6001234500012").map(&:name), "by barcode"
    assert_empty Product.search("hammer"), "Bolt's hammer isn't Acme's"
    assert_equal [ "Bamburi cement 50kg" ], Product.search("cem-50").map(&:name), "by SKU, any case"

    assert_equal [ customers(:acme_contractor) ], Customer.search("mwangi").to_a
    assert_equal [ customers(:acme_contractor) ], Customer.search("0722 000 111").to_a, "by the phone's last digits"
    assert_empty Customer.search("nobody")
    assert_equal [ suppliers(:acme_cement_distributor) ], Supplier.search("cement").to_a

    Current.account = accounts(:bolt)
    assert_equal [ "Claw hammer 16oz" ], Product.search("hammer").map(&:name)
    assert_empty Product.search("nail")
  end

  test "with a big catalogue, the search runs on the trigram indexes" do
    unit = units(:acme_kg)
    rows = 6_000.times.map { |i| { account_id: accounts(:acme).id, unit_id: unit.id, name: "Load item #{i} #{%w[ paint pipe nail bolt ][i % 4]}", sku: "LT-#{i}", price_cents: 100, created_at: Time.current, updated_at: Time.current } }
    Product.insert_all(rows)
    ActiveRecord::Base.connection.execute "ANALYZE products"

    # With a table scan ruled out, the planner shows whether the trigram indexes are usable at all. As the
    # functions' owner (no row security) they are; under row security the same condition can't use them,
    # which is why searches go through the functions.
    connection = ActiveRecord::Base.connection
    connection.execute "SET enable_seqscan = off"
    connection.execute "SET ROLE #{SearchFunctions::ROLE}"
    plan = connection.select_values("EXPLAIN SELECT p.id FROM products p WHERE p.name ILIKE '%zinc%' OR p.sku ILIKE '%zinc%'").join("\n")
    connection.execute "RESET ROLE"
    assert_match(/Bitmap Index Scan on index_products_on_(name|sku_trigram)/, plan, plan)

    plan = connection.select_values("EXPLAIN SELECT p.id FROM products p WHERE (p.name ILIKE '%zinc%' OR p.sku ILIKE '%zinc%')").join("\n")
    assert_no_match(/index_products_on_(name|sku_trigram)/, plan, plan)
    connection.execute "RESET enable_seqscan"

    assert_equal 1_501, Product.search("nail").count, "1,500 load items and the fixture's wire nails"
    assert_equal [ "Load item 4123 bolt" ], Product.search("item 4123").map(&:name)
  end
end
