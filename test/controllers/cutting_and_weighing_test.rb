require "test_helper"

class CuttingAndWeighingTest < ActionDispatch::IntegrationTest
  setup do
    @bar = Account.without_isolation do
      Current.set(account: accounts(:acme)) do
        metre = accounts(:acme).units.create!(name: "Metre", abbreviation: "m", fractional: true)
        accounts(:acme).update!(features: accounts(:acme).features + [ "cutting" ])
        accounts(:acme).products.create!(name: "Y12 steel bar", sku: "Y12", unit: metre, price_cents: 20000, cost_cents: 15000, stock_length: 6, quick_pick: true)
      end
    end
    stock_up @bar, 30
  end

  def acme(&block) = Account.without_isolation { Current.set(account: accounts(:acme), &block) }
  def current_sale = acme { shifts(:acme_front_open).sales.find_by!(status: "open") }

  def at_the_till
    sign_in_as users(:carl)
    post pos_till_path, params: { register_id: registers(:acme_front).id }
  end

  test "the till asks a cut product for pieces and a length, and the sale page says what to cut from" do
    at_the_till
    get pos_products_path
    assert_select "form[data-stock-length='6'][data-rack='5 full lengths']"
    assert_select "input[name=pieces]"
    assert_select "input[name=cut_length]"

    post pos_lines_path, params: { product_id: @bar.id, pieces: 3, cut_length: "2.5" }, as: :turbo_stream
    assert_response :success
    assert_match "Y12 steel bar · 3 × 2.5 m", response.body
    assert_select "input[name='sale_line[pieces]'][value='3']"
    assert_select "input[name='sale_line[cut_length]'][value='2.5'][max='6']"
    line = acme { current_sale.lines.sole }
    assert_equal [ 7.5, 2.5, 150_000 ], [ line.quantity.to_f, line.cut_length.to_f, line.total_cents ]

    patch pos_line_path(line), params: { sale_line: { pieces: 2, cut_length: "4" } }, as: :turbo_stream
    assert_equal [ 8, 4, 160_000 ], acme { line.reload.then { [ _1.quantity.to_i, _1.cut_length.to_i, _1.total_cents ] } }

    patch pos_line_path(line), params: { sale_line: { pieces: 1, cut_length: "7" } }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_match "comes in lengths of 6 m", response.body

    sale = current_sale
    post pos_payments_path, params: { tender: "cash", tendered: "2000" }
    follow_redirect!
    assert_select "#completed_sale", /To cut.*Y12 steel bar:.*2 × 4 m cut from a 6 m length, leaving a 2 m offcut/m

    get sale_path(sale)
    assert_select "li", /2 × 4 m cut from a 6 m length, leaving a 2 m offcut/
  end

  test "scanning a cut product adds one full length" do
    at_the_till
    post pos_lines_path, params: { code: "y12" }, as: :turbo_stream
    assert_equal [ 6, 6 ], acme { current_sale.lines.sole.then { [ _1.quantity.to_i, _1.cut_length.to_i ] } }
  end

  test "a product's page lists its lengths and offcuts, and a stock manager keeps them right" do
    sign_in_as users(:amina)
    main = branches(:acme_main)

    post product_offcuts_path(@bar), params: { branch_id: main.id, length: "3.5" }
    assert_redirected_to @bar
    follow_redirect!
    assert_select "section", /Lengths and offcuts.*Comes in 6 m lengths/m
    assert_select "span.badge", /3\.5 m/
    assert_select "span.badge", /2\.5 m part length/

    post product_offcuts_path(@bar), params: { branch_id: main.id, length: "9" }
    assert_match "shorter than the 6 m it comes in", flash[:alert]

    offcut = acme { @bar.offcuts.sole }
    delete product_offcut_path(@bar, offcut, scrap: 1)
    assert_equal [ 26.5, 0 ], acme { [ @bar.stock_at(main).to_f, @bar.offcuts.count ] }

    post product_offcuts_path(@bar), params: { branch_id: main.id, length: "1" }
    delete product_offcut_path(@bar, acme { @bar.offcuts.sole })
    assert_equal [ 26.5, 0 ], acme { [ @bar.stock_at(main).to_f, @bar.offcuts.count ] }, "taken off the list, the stock stays"
  end

  test "cashiers can't change offcuts, and another shop's product isn't found" do
    sign_in_as users(:carl)
    post product_offcuts_path(@bar), params: { branch_id: branches(:acme_main).id, length: "2" }
    assert_equal 0, acme { @bar.offcuts.count }

    sign_in_as users(:amina)
    post product_offcuts_path(products(:bolt_hammer)), params: { branch_id: branches(:acme_main).id, length: "2" }
    assert_response :not_found
  end

  test "the product form sets the length it comes in, once cutting is switched on" do
    sign_in_as users(:amina)
    get edit_product_path(@bar)
    assert_select "input[name='product[stock_length]'][value='6']"

    patch product_path(@bar), params: { product: { stock_length: "5.8", scrap_below: "0.3" } }
    assert_equal [ 5.8, 0.3 ], acme { @bar.reload.then { [ _1.stock_length.to_f, _1.scrap_below.to_f ] } }

    get edit_product_path(products(:acme_cement))
    assert_select "input[name='product[stock_length]']"
    acme { @bar.update!(stock_length: nil); accounts(:acme).update!(features: accounts(:acme).features - [ "cutting" ]) }
    get edit_product_path(products(:acme_cement))
    assert_select "input[name='product[stock_length]']", count: 0
  end

  test "a till with a scale offers Weigh for what's sold by the kilogram" do
    sign_in_as users(:amina)
    patch register_path(registers(:acme_front)), params: { register: { scale_mode: "continuous", scale_baud_rate: 4800, scale_framing: "7E1" } }
    assert_redirected_to registers_path
    assert_equal [ "continuous", 4800, "7E1" ], acme { registers(:acme_front).reload.then { [ _1.scale_mode, _1.scale_baud_rate, _1.scale_framing ] } }

    patch register_path(registers(:acme_front)), params: { register: { scale_mode: "bluetooth" } }
    assert_response :unprocessable_entity

    at_the_till
    get pos_products_path
    assert_select "[data-controller=scale][data-scale-mode-value=continuous][data-scale-baud-rate-value='4800'][data-scale-framing-value='7E1'] button[data-action='scale#read']", "Weigh"

    post pos_lines_path, params: { code: "nail-3" }, as: :turbo_stream
    post pos_lines_path, params: { code: "cem-50" }, as: :turbo_stream
    assert_select "form[data-controller~=scale][data-scale-per-kilogram-value='1'] button[data-action='scale#read']", count: 1

    get pos_path
    assert_match "serial=(self)", response.headers["Permissions-Policy"]
  end

  test "a till without a scale has no Weigh button" do
    at_the_till
    get pos_products_path
    assert_select "button[data-action='scale#read']", count: 0
    post pos_lines_path, params: { code: "nail-3" }, as: :turbo_stream
    assert_select "button[data-action='scale#read']", count: 0
  end
end
