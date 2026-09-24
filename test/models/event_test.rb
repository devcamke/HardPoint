require "test_helper"

class EventTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = Account.without_isolation { accounts(:acme).sessions.create!(user: users(:amina)) }
  end

  test "creating, changing and removing records is recorded with who did it" do
    branch = accounts(:acme).branches.create!(name: "Westlands")
    branch.update!(name: "Westlands Mall")
    branch.destroy!

    events = accounts(:acme).account_events.where(eventable: branch).order(:id)
    assert_equal %w[ created updated destroyed ], events.map(&:action)
    assert_equal [ users(:amina) ], events.map(&:creator).uniq
    assert_equal({ "name" => [ "Westlands", "Westlands Mall" ] }, events.second.particulars["changes"])
    assert_equal "Westlands Mall", events.last.particulars["name"]
  end

  test "role changes are recorded" do
    memberships(:carl_acme).update!(role: :manager)

    event = accounts(:acme).account_events.where(eventable: memberships(:carl_acme)).last
    assert_equal({ "role" => %w[ cashier manager ] }, event.particulars["changes"])
  end

  test "events can't be edited or deleted" do
    event = accounts(:acme).account_events.last

    assert_raises(ActiveRecord::ReadOnlyRecord) { event.update!(action: "tampered") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { event.destroy! }
  end

  test "secrets never end up in the audit trail" do
    memberships(:carl_acme).set_pin("9999")

    assert accounts(:acme).account_events.none? { |event| event.particulars.to_s.include?("digest") }
  end
end
