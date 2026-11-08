require "test_helper"

class AlertsTest < ActiveSupport::TestCase
  setup do
    @cache, Rails.cache = Rails.cache, ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @cache }

  test "an alert is emailed to the operators straight away, once an hour per key" do
    assert_difference -> { ActionMailer::Base.deliveries.size }, 2 do
      assert Alerts.notify("health:queue", "Queue check failing", "No worker has sent a heartbeat")
      assert_not Alerts.notify("health:queue", "Queue check failing", "Still none"), "the same alert within the hour is dropped"
      assert Alerts.notify("health:disk", "Disk check failing", "95% used"), "a different alert goes"
    end

    mail = ActionMailer::Base.deliveries[-2]
    assert_equal [ "support@hardpoint.app" ], mail.to
    assert_equal "[HardPoint test] Queue check failing", mail.subject
    assert_match "No worker has sent a heartbeat", mail.body.to_s
    assert_match "once an hour", mail.body.to_s

    travel 61.minutes do
      assert Alerts.notify("health:queue", "Queue check failing", "Still none"), "sent again after the hour"
    end
  end

  test "errors reported to Rails.error become alerts, but not expected ones or warnings" do
    subscriber = Alerts::ErrorSubscriber.new

    assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
      error = begin; raise NoMethodError, "undefined method `pay' for nil"; rescue => e; e; end
      subscriber.report(error, handled: false, severity: :error, context: { account_id: 1 }, source: "application.action_dispatch")
      subscriber.report(error, handled: false, severity: :error, context: {}, source: "application.action_dispatch") # same place: throttled
      subscriber.report(ActiveRecord::RecordNotFound.new("nope"), handled: false, severity: :error, context: {})
      subscriber.report(error, handled: true, severity: :warning, context: {})
    end

    mail = ActionMailer::Base.deliveries.last
    assert_match "NoMethodError: undefined method `pay' for nil", mail.subject
    assert_match "Unhandled in application.action_dispatch", mail.body.to_s
    assert_match "account_id=1", mail.body.to_s
    assert_match "alerts_test.rb", mail.body.to_s
  end

  test "a job that gives up is reported with its name" do
    reported = []
    subscriber = Object.new
    subscriber.define_singleton_method(:report) { |error, **details| reported << [ error, details ] }
    Rails.error.subscribe(subscriber)

    job_class = Class.new(ApplicationJob) do
      def self.name = "ExplodingJob"
      def perform = raise ArgumentError, "boom"
    end

    assert_raises(ArgumentError) { job_class.perform_now }
    error, details = reported.sole
    assert_equal "boom", error.message
    assert_equal [ "ExplodingJob", :error, "application.active_job" ], [ details[:context][:job], details[:severity], details[:source] ]
  ensure
    Rails.error.unsubscribe(subscriber)
  end

  test "a failing platform check pages the operators" do
    Account.without_isolation do
      Current.set(account: accounts(:acme), user: users(:amina)) do
        accounts(:acme).account_backups.create!(kind: "manual", status: "failed", requested_by: users(:amina), failure: "bucket said no")
      end
    end

    assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
      PlatformHealthJob.perform_now
    end
    assert_match "Backups check failing: 1 shop backups failed", ActionMailer::Base.deliveries.last.subject
    assert_match "ok       database", ActionMailer::Base.deliveries.last.body.to_s
  end
end
