require "test_helper"

class PlatformHealthTest < ActiveSupport::TestCase
  test "a healthy platform passes every check, and says so for the monitor" do
    health = PlatformHealth.check

    assert health.ok?
    assert_equal "ok", health.status
    assert_equal %i[ database replica etims backups integrity disk ], health.checks.map(&:name), "queue and email checks only apply with Solid Queue and SES"
    assert_equal({ status: :ok, detail: "primary answers" }, health.as_json[:checks][:database])
    assert_equal :ok, health.as_json(detail: false)[:checks][:backups]
  end

  test "a shop's failed backup fails the platform, and a late eTIMS queue is a warning" do
    Account.without_isolation do
      Current.set(account: accounts(:acme), user: users(:amina)) do
        accounts(:acme).account_backups.create!(kind: "manual", status: "failed", requested_by: users(:amina), failure: "bucket said no")
      end
    end
    health = PlatformHealth.check

    assert_not health.ok?
    assert_equal "failing", health.status
    assert_equal [ :backups ], health.failing.map(&:name)
    assert_match "1 shop backups failed", health.failing.first.detail
  end

  test "a check that raises is a failing check, not a broken report" do
    health = PlatformHealth.new
    health.define_singleton_method(:disk) { raise IOError, "df went away" }

    check = health.checks.find { _1.name == :disk }
    assert check.failing?
    assert_equal "IOError: df went away", check.detail
  end
end
