require "test_helper"

class NavigationTest < ActionDispatch::IntegrationTest
  test "owners see the six areas, with Settings under the gear" do
    sign_in_as users(:amina)
    get root_path

    assert_select "nav a[href='#{root_path}']", text: "Home"
    %w[ Sell Customers Stock Buy Reports ].each { assert_select "nav a", text: _1 }
    assert_select "nav a[aria-label=Settings][href='#{settings_path}']"
    assert_select "nav a", text: "Open till"
    %w[ Inventory Purchase Employees ].each { assert_select "nav a", text: _1, count: 0 }
  end

  test "an area shows its own menu, with the current page marked" do
    sign_in_as users(:amina)
    get products_path

    assert_select "nav a[aria-current=page]", text: "Stock"
    assert_select "nav [aria-label='Stock menu'] a[aria-current=page]", text: "Products"
    assert_select "nav [aria-label='Stock menu'] a", text: "Reorder"
    %w[ Categories Brands Units ].each { assert_select "nav [aria-label='Stock menu'] a", text: _1, count: 0 }
  end

  test "catalogue lists, staff and activity live under Settings" do
    sign_in_as users(:amina)

    get categories_path
    assert_select "nav a[aria-label=Settings].bg-white\\/20"

    get memberships_path
    assert_select "nav [aria-label='Settings menu'] a[aria-current=page]", text: "Staff"
    assert_select "nav [aria-label='Settings menu'] a", text: "Activity"
  end

  test "pages reached from inside an area keep that area highlighted" do
    sign_in_as users(:amina)

    get supplier_invoices_path
    assert_select "nav a[aria-current=page]", text: "Buy"

    get stock_movements_path
    assert_select "nav a[aria-current=page]", text: "Stock"
  end

  test "cashiers only see the areas they work in" do
    sign_in_as users(:carl)
    get root_path

    %w[ Home Sell Customers Stock ].each { assert_select "nav a", text: _1 }
    %w[ Buy Reports ].each { assert_select "nav a", text: _1, count: 0 }
  end
end
