require "test_helper"

class SessionsRateLimitTest < ActionDispatch::IntegrationTest
  # Tests use a null cache, which never counts; count in memory for these tests only.
  setup do
    counts = ActiveSupport::Cache::MemoryStore.new
    SessionsController.cache_store.define_singleton_method(:increment) { |*args, **options| counts.increment(*args, **options) }
    use_account accounts(:acme)
  end

  teardown { SessionsController.cache_store.singleton_class.remove_method(:increment) }

  test "a busy shop's staff can all sign in from one address, but one login can't be guessed at" do
    12.times { |i| post session_path, params: { email_address: "nobody#{i}@acme.test", password: "wrong" } }
    post session_path, params: { email_address: users(:carl).email_address, password: "password" }
    assert cookies[:session_id].present?, "the 13th person at the shop still signs in"

    10.times { post session_path, params: { email_address: users(:amina).email_address, password: "wrong" } }
    post session_path, params: { email_address: users(:amina).email_address, password: "password" }
    assert_equal "Try again later.", flash[:alert]
  end
end
