require "test_helper"

# Search finds products and customers by the start of their words, kept in search_terms by database triggers.
class SearchTermTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:amina))
  end

  def terms_for(record) = SearchTerm.where(record_type: record.class.table_name, record_id: record.id).pluck(:term).sort

  test "a product's terms are the words of its name and SKU, and its SKU's parts" do
    assert_equal %w[ 2 6m inch pipe pvc pvc-2 ], terms_for(products(:acme_pipe))
  end

  test "renaming a product, or deleting it, changes its terms" do
    pipe = products(:acme_pipe)
    pipe.update!(name: "Waste pipe 4 inch")
    assert_includes terms_for(pipe), "waste"
    assert_not_includes terms_for(pipe), "6m"
    assert_equal [ pipe ], Product.search("waste 4").to_a
    assert_empty Product.search("waste 6m"), "6m left the name"

    tap = accounts(:acme).products.create!(name: "Garden tap", sku: "TAP-1", unit: units(:acme_piece), price_cents: 1200_00)
    assert_equal [ tap ], Product.search("gard").to_a
    tap.destroy!
    assert_empty terms_for(tap)
  end

  test "words are matched from their start, and the SKU in part or whole" do
    assert_equal [ products(:acme_pipe) ], Product.search("PV 2 inc").to_a
    assert_equal [ products(:acme_cement) ], Product.search("CEM-5").to_a
    assert_equal [ products(:acme_cement) ], Product.search("50kg bamb").to_a
  end

  test "when no word starts that way, a word anywhere in the name still finds it" do
    assert_equal [ products(:acme_cement) ], Product.search("buri").to_a
  end

  test "imports, which skip callbacks, still give their products terms" do
    import = accounts(:acme).product_imports.create!(branch: branches(:acme_main), filename: "taps.csv", csv: <<~CSV)
      sku,name,unit,price
      TAP-1,Garden tap brass,Piece,1200
    CSV
    import.check
    import.update!(status: :importing)
    import.run
    assert_equal [ "TAP-1" ], Product.search("brass gard").pluck(:sku)
  end

  test "customers are found by the start of a name word or of their number, however it's written" do
    contractor = customers(:acme_contractor) # +254722000111
    assert_includes terms_for(contractor), "722000111"
    [ "mwan", "Builders mwangi", "0722 000", "+254 722 000 111", "722000" ].each do |query|
      assert_includes Customer.search(query), contractor, query
    end
    assert_includes Customer.search("000 111"), contractor, "the middle of a number, found the slow way"

    contractor.update!(phone: "0733 123 456")
    assert_includes Customer.search("0733123"), contractor
    assert_not_includes Customer.search("0722000"), contractor
  end
end
