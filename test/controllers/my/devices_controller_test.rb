require "test_helper"

class My::DevicesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:amina) }

  # Row-level security applies to the test's own queries too, so they run with it bypassed, to completion.
  def amina_session_ids = Account.without_isolation { accounts(:acme).sessions.where(user: users(:amina)).pluck(:id) }

  test "lists where you're signed in and signs out one device, or all the others" do
    phone = Account.without_isolation do
      Current.set(account: accounts(:acme)) do
        accounts(:acme).sessions.create!(user: users(:amina), user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
          ip_address: "41.90.1.2", created_at: 3.days.ago, last_seen_at: 2.days.ago)
      end
    end

    get my_devices_path
    assert_response :success
    assert_select "##{dom_id(phone)}", /Safari on iPhone/
    assert_select "##{dom_id(phone)}", /41\.90\.1\.2/
    assert_select "tr", /This device/
    assert_select "form[action=?]", my_device_path("others")

    delete my_device_path(phone)
    assert_redirected_to my_devices_path
    assert_not_includes amina_session_ids, phone.id

    get my_profile_path
    assert_select "section", /Signed-in devices\s*.*1 device/m
  end

  test "signing out everywhere else keeps this device" do
    2.times { Account.without_isolation { Current.set(account: accounts(:acme)) { accounts(:acme).sessions.create!(user: users(:amina)) } } }
    assert_equal 3, amina_session_ids.size

    delete my_device_path("others")
    assert_redirected_to my_devices_path
    assert_equal 1, amina_session_ids.size

    get root_path
    assert_response :success, "still signed in here"
  end

  test "you can't sign out someone else's device" do
    carl = Account.without_isolation { Current.set(account: accounts(:acme)) { accounts(:acme).sessions.create!(user: users(:carl)) } }

    delete my_device_path(carl)
    assert_response :not_found
    assert Account.without_isolation { Session.exists?(carl.id) }
  end
end
