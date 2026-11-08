require "test_helper"

class SessionExpiryTest < ActionDispatch::IntegrationTest
  test "a session that hasn't been used for two weeks asks you to sign in again" do
    sign_in_as users(:amina)
    get root_path
    assert_response :success

    Account.without_isolation { accounts(:acme).sessions.where(user: users(:amina)).update_all(last_seen_at: 15.days.ago) }
    get root_path
    assert_redirected_to new_session_path
    assert_equal 0, Account.without_isolation { accounts(:acme).sessions.where(user: users(:amina)).count }, "the expired session is removed"
  end
end
