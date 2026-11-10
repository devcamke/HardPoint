require "test_helper"

class SessionTest < ActiveSupport::TestCase
  setup { Current.account = accounts(:acme) }

  test "a session ends after two weeks unused, or three months in all" do
    session = accounts(:acme).sessions.create!(user: users(:amina))
    assert_not session.expired?

    session.update_columns(last_seen_at: 15.days.ago)
    assert session.expired?
    assert_includes Session.expired, session

    session.update_columns(last_seen_at: 1.hour.ago, created_at: 91.days.ago)
    assert session.expired?

    session.update_columns(created_at: 1.day.ago)
    assert_not session.expired?
    assert_not_includes Session.expired, session
  end

  test "last_seen_at is refreshed at most once an hour" do
    session = accounts(:acme).sessions.create!(user: users(:amina))
    session.update_columns(last_seen_at: 30.minutes.ago)
    session.seen
    assert_in_delta 30.minutes.ago, session.reload.last_seen_at, 1.minute

    session.update_columns(last_seen_at: 2.hours.ago)
    session.seen
    assert_in_delta Time.current, session.reload.last_seen_at, 1.minute
  end

  test "the nightly purge removes sessions nobody came back to" do
    stale = accounts(:acme).sessions.create!(user: users(:amina))
    stale.update_columns(last_seen_at: 20.days.ago)
    live = accounts(:acme).sessions.create!(user: users(:amina))

    Account.without_isolation { Session.purge_expired }

    assert_not Session.exists?(stale.id)
    assert Session.exists?(live.id)
  end

  test "devices are named from the browser" do
    assert_equal "Chrome on Windows", Session.new(user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36").device
    assert_equal "Chrome on Android", Session.new(user_agent: "Mozilla/5.0 (Linux; Android 14; SM-A546B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36").device
    assert_equal "A browser", Session.new(user_agent: nil).device
  end
end
