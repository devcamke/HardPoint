require "test_helper"

class DashboardChannelTest < ActionCable::Channel::TestCase
  def signed(account)
    Turbo::StreamsChannel.signed_stream_name([ account, :dashboard ])
  end

  test "streams a shop's dashboard to its owner" do
    stub_connection current_account: accounts(:acme), current_user: users(:amina)
    subscribe signed_stream_name: signed(accounts(:acme))

    assert subscription.confirmed?
    assert_has_stream "#{accounts(:acme).to_gid_param}:dashboard"
  end

  test "refuses cashiers, and another shop's dashboard even with a valid signature" do
    stub_connection current_account: accounts(:acme), current_user: users(:carl)
    subscribe signed_stream_name: signed(accounts(:acme))
    assert subscription.rejected?

    stub_connection current_account: accounts(:acme), current_user: users(:amina)
    subscribe signed_stream_name: signed(accounts(:bolt))
    assert subscription.rejected?
  end
end
