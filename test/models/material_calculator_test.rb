require "test_helper"

class MaterialCalculatorTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:amina))
  end

  def materials(values) = MaterialCalculator.part_class(values[:kind]).new(values).materials.transform_values { _1.to_d.round(2) }

  test "a wall of 9x9 stone: about 9.6 stones a square metre less the openings, plus mortar" do
    wall = materials(kind: "wall", length: "10", height: "3", openings: "2", unit: "stone_9x9")
    assert_equal ((28 / (0.462 * 0.237)) * 1.05).ceil, wall["stone_9x9"]
    assert_in_delta 3.8, wall["cement"], 0.1, "bags of cement for the mortar: about 7.4 m² a bag"
    assert_in_delta 0.85, wall["sand"], 0.05, "tonnes of sand"
  end

  test "concrete at 1:2:4: cement, sand and ballast from the volume, and bars both ways with laps" do
    slab = materials(kind: "concrete", length: "5", width: "4", thickness: "0.15", mix: "1:2:4", steel: "bar_y12", spacing: "200")
    dry = 3 * 1.54 * 1.05
    assert_in_delta dry / 7 * 1440 / 50, slab["cement"], 0.01
    assert_in_delta dry * 4 / 7 * 1.5, slab["ballast"], 0.01
    metres = (21 * 5 + 26 * 4) * 1.1 # 21 bars of 5 m across the 4 m, 26 of 4 m across the 5 m
    assert_equal (metres / 12).ceil, slab["bar_y12"]
    assert_equal 3, slab["binding_wire"], "204 kg of Y12 at 1 kg of wire per 100 kg"

    mesh = materials(kind: "concrete", length: "5", width: "4", thickness: "0.1", steel: "brc_a142")
    assert_equal 2, mesh["brc_a142"], "20 m² with overlaps, at 11.52 m² a sheet"
  end

  test "a gable roof: sheets across times sheets up each side, ridge caps and nails" do
    roof = materials(kind: "roof", length: "9", slope: "4", slopes: "2", sheet_length: "3", cover: "0.76")
    assert_equal 12 * 2 * 2, roof["iron_sheet"], "12 across, 2 up (3 m then 1 m with a 15 cm lap), both sides"
    assert_equal 5, roof["ridge_cap"]
    assert_equal 5, roof["roofing_nails"]
  end

  test "plaster, tiles and paint" do
    assert_in_delta 6.3, materials(kind: "plaster", area: "50", thickness: "15")["cement"], 0.1, "about 8 m² a bag at 15 mm"
    tiles = materials(kind: "tiles", area: "40")
    assert_equal [ 44, 11, 22 ], [ tiles["tiles"], tiles["tile_adhesive"], tiles["tile_grout"] ]
    assert_in_delta 22, materials(kind: "paint", area: "100", coats: "2", coverage: "10")["paint"], 0.01
  end

  test "a part left empty, or with nonsense, is skipped" do
    estimate = MaterialCalculator::Estimate.new(accounts(:acme), [ { "kind" => "wall" }, { "kind" => "tiles", "area" => "abc" }, { "kind" => "nope" } ])
    assert_empty estimate.filled_parts
    assert_empty estimate.lines
  end

  test "materials become the shop's products, whole ones rounded up and others converted, and the quote lists what was measured" do
    accounts(:acme).material_products.create!(material: "paint", product: products(:acme_nails), factor: 0.05) # sold in 20-litre tins
    accounts(:acme).material_products.create!(material: "tiles", product: products(:acme_screws), factor: 1)

    estimate = MaterialCalculator::Estimate.new(accounts(:acme), [ { "kind" => "paint", "area" => "100" }, { "kind" => "tiles", "area" => "10" } ])
    paint = estimate.lines.find { _1.material.key == "paint" }
    assert_equal 1.1, paint.sell_quantity, "22 litres is 1.1 of a 20-litre tin, by the kg-sold stand-in"
    tiles = estimate.lines.find { _1.material.key == "tiles" }
    assert_equal 11, tiles.sell_quantity, "screws are sold whole, so 11 m² of tiles rounds up"
    assert_equal [ "tile_adhesive", "tile_grout" ], estimate.unmapped.map { _1.material.key }

    quote = estimate.to_quote(customer: customers(:acme_contractor), branch: branches(:acme_main))
    assert quote.save, quote.errors.full_messages.to_sentence
    assert quote.quote?
    assert_equal 2, quote.lines.size
    assert_match "Painting, 100 m², 2 coats; Tiling, 10 m²", quote.note
  end
end
