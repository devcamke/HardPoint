require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
  test "owners see their shop's activity" do
    sign_in_as users(:amina)
    patch branch_path(branches(:acme_yard)), params: { branch: { name: "Steel yard" } }

    get events_path

    assert_response :success
    assert_select "li", /Amina Owner changed branch Steel yard: name from “Timber yard” to “Steel yard”/
    assert_select "li", /Amina Owner signed in/
  end

  test "another shop's activity isn't shown" do
    sign_in_as users(:bob)
    sign_in_as users(:amina)

    get events_path

    assert_select "li", text: /Bob Owner/, count: 0
  end

  test "cashiers can't see activity" do
    sign_in_as users(:carl)
    get events_path
    assert_response :forbidden
  end
end
