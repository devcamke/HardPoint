require "test_helper"

class ToursControllerTest < ActionDispatch::IntegrationTest
  test "the guided tours a cashier can take, from the menu under their name" do
    sign_in_as users(:carl)
    get root_path
    assert_select "#user-menu a[href=?]", tours_path, text: "Guided tours"
    assert_select "#user-menu a[href=?]", "http://localhost/help", text: "Help"

    get tours_path
    assert_response :success
    assert_select "a[href=?][data-guided-tour-start]", "/?tour=home", text: "Start the tour"
    assert_select "a[href=?][data-guided-tour-start]", "/pos?tour=till", text: "Start the tour"
    assert_select "a[href=?][data-guided-tour-start]", "/products?tour=products", text: "Start the tour"
    assert_select "a[href*='tour=stock-take']", count: 0
    assert_select "a[href*='tour=receiving']", count: 0
  end

  test "stock clerks get stock takes and receiving, which start from their lists" do
    sign_in_as users(:sara)
    get tours_path

    assert_select "a[href=?][data-guided-tour-start]", "/stock_counts?tour=stock-take", text: "Start the tour"
    assert_select "a[href=?][data-guided-tour-start]", "/goods_receipts?tour=receiving", text: "Start the tour"
    data = JSON.parse(css_select("a[href='/stock_counts?tour=stock-take']").first["data-guided-tour-start"])
    assert_equal "^/stock_counts/[^/]+$", data["page_pattern"]
    assert_match "press New", data["waiting"]
  end

  test "accountants aren't offered the till" do
    Account.without_isolation { memberships(:carl_acme).update!(role: "accountant") }
    sign_in_as users(:carl)

    get tours_path
    assert_select "a[href=?]", "/pos?tour=till", count: 0
    assert_select "a[href=?]", "/?tour=home"
  end

  test "?tour= starts a tour, with its steps and the guide behind it" do
    sign_in_as users(:amina)
    get root_path(tour: "home")

    data = JSON.parse(css_select("[data-controller=guided-tour]").first["data-guided-tour-tour-value"])
    assert_equal "home", data["id"]
    assert_equal HelpTour.find("home").steps.map(&:target), data["steps"].pluck("target")
    assert_equal "http://localhost/help/getting-around#walkthrough-home", data["guide_url"]

    get root_path(tour: "nonsense")
    assert_nil css_select("[data-controller=guided-tour]").first["data-guided-tour-tour-value"]
  end

  # The tours point at data-tour="…" on their screens: renaming or removing one would quietly skip a step.
  test "every step's button is on its screen, for the owner" do
    sign_in_as users(:amina)
    post pos_till_path, params: { register_id: registers(:acme_front).id }

    post stock_counts_path, params: { stock_count: { branch_id: branches(:acme_main).id, category_id: categories(:acme_fasteners).id } }
    screens = { "stock-take" => stock_count_path(Account.without_isolation { StockCount.last }) }

    HelpTour.all.each do |tour|
      screen = screens.fetch(tour.id, tour.page)
      assert tour.runs_on?(screen), "#{tour.id} should run on #{screen}"
      get screen
      assert_response :success, "#{tour.id}: #{screen}"
      body = response.body
      if tour.id == "till"
        # Payment only shows once something's in the sale, and the products come in after the page.
        post pos_lines_path, params: { code: "nail-3" }, as: :turbo_stream
        get pos_path
        body = response.body
        get pos_products_path
        body += response.body
      end
      tour.steps.each do |step|
        assert_includes body, %(data-tour="#{step.target}"), "#{tour.id}: nothing on #{screen} has data-tour=\"#{step.target}\""
      end
    end
  end
end
