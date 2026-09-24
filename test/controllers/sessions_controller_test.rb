require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { use_account accounts(:acme) }

  test "new" do
    get new_session_path
    assert_response :success
    assert_select "h1", "Sign in to Acme Hardware"
  end

  test "unknown shops are not found" do
    host! "nowhere.localhost"
    get new_session_path
    assert_response :not_found
  end

  test "create with valid credentials" do
    post session_path, params: { email_address: users(:amina).email_address, password: "password" }

    assert_redirected_to root_url
    assert cookies[:session_id]
  end

  test "create with invalid credentials" do
    post session_path, params: { email_address: users(:amina).email_address, password: "wrong" }

    assert_redirected_to new_session_path(email_address: users(:amina).email_address)
    assert_nil cookies[:session_id]
  end

  test "people can't sign in to a shop they don't belong to" do
    post session_path, params: { email_address: users(:bob).email_address, password: "password" }

    assert_redirected_to new_session_path(email_address: users(:bob).email_address)
    assert_nil cookies[:session_id]
  end

  test "a session from one shop doesn't sign you in to another" do
    sign_in_as users(:amina), account: accounts(:acme)
    get root_path
    assert_response :success

    use_account accounts(:bolt)
    get root_path
    assert_redirected_to new_session_path
  end

  test "destroy" do
    sign_in_as users(:amina)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end
end
