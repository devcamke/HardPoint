require "test_helper"

class My::ProfilesControllerTest < ActionDispatch::IntegrationTest
  test "an owner's profile shows each setting's status as a dot" do
    sign_in_as users(:amina)
    get my_profile_path

    assert_response :success
    assert_select "section", /Approval PIN\s*.*Not set/m
    assert_select "span.rounded-full.bg-gray-300", minimum: 1
  end

  test "a cashier's profile shows their till PIN is set" do
    sign_in_as users(:carl)
    get my_profile_path

    assert_response :success
    assert_select "span.rounded-full.bg-green-600", minimum: 1
  end
end
