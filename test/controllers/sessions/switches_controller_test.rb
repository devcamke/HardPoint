require "test_helper"

class Sessions::SwitchesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:amina) }

  test "lists staff who have a PIN" do
    get new_session_switch_path

    assert_response :success
    assert_select "label", /Carl Cashier/
    assert_select "label", /Sara Stockclerk/
  end

  test "switching in with the right PIN" do
    post session_switch_path, params: { membership_id: memberships(:carl_acme).id, pin: "1234" }

    assert_redirected_to root_path
    follow_redirect!
    assert_select "h1", "Welcome, Carl Cashier"
    assert Account.without_isolation { Event.exists?(action: "switched_in", creator: users(:carl)) }
  end

  test "a wrong PIN keeps the current person signed in" do
    post session_switch_path, params: { membership_id: memberships(:carl_acme).id, pin: "0000" }

    assert_redirected_to new_session_switch_path
    get root_path
    assert_select "h1", "Welcome, Amina Owner"
  end

  test "PINs lock after too many wrong tries" do
    Membership::PIN_ATTEMPTS_ALLOWED.times do
      post session_switch_path, params: { membership_id: memberships(:carl_acme).id, pin: "0000" }
    end

    post session_switch_path, params: { membership_id: memberships(:carl_acme).id, pin: "1234" }

    assert_match "locked", flash[:alert]
    get root_path
    assert_select "h1", "Welcome, Amina Owner"
  end

  test "can't switch into an owner or someone from another shop" do
    post session_switch_path, params: { membership_id: memberships(:amina_acme).id, pin: "1234" }
    assert_response :not_found

    post session_switch_path, params: { membership_id: memberships(:bob_bolt).id, pin: "1234" }
    assert_response :not_found
  end

  test "switching needs a signed-in till" do
    sign_out
    post session_switch_path, params: { membership_id: memberships(:carl_acme).id, pin: "1234" }
    assert_redirected_to new_session_path
  end
end
