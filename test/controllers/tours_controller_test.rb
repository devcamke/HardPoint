require "test_helper"

class ToursControllerTest < ActionDispatch::IntegrationTest
  test "the guided tours a cashier can take, from the menu under their name" do
    sign_in_as users(:carl)
    get root_path
    assert_select "#user-menu a[href=?]", tours_path, text: "Guided tours"
    assert_select "#user-menu a[href=?]", "http://localhost/help", text: "Help"

    get tours_path
    assert_response :success
    HelpTour.all.each do |tour|
      assert_select "a[href=?][data-guided-tour-start]", "#{tour.page}?tour=#{tour.id}", text: "Start the tour"
    end
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

    HelpTour.all.each do |tour|
      get tour.page
      assert_response :success, "#{tour.id}: #{tour.page}"
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
        assert_includes body, %(data-tour="#{step.target}"), "#{tour.id}: nothing on #{tour.page} has data-tour=\"#{step.target}\""
      end
    end
  end
end
