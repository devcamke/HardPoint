require "test_helper"

# The Sentry initializer only runs with a DSN, so tests would never see a setting the gem no longer knows; this
# runs it once with a dummy DSN (nothing is sent: no event is captured) and checks the configuration took.
class SentryConfigTest < ActiveSupport::TestCase
  test "the initializer configures Sentry without PII and with the release and environment" do
    ENV["SENTRY_DSN"] = "https://examplePublicKey@o0.ingest.sentry.io/0"
    load Rails.root.join("config/initializers/sentry.rb")

    assert Sentry.initialized?
    configuration = Sentry.configuration
    assert_equal false, configuration.send_default_pii
    assert_equal Rails.configuration.x.release, configuration.release
    assert_equal "test", configuration.environment
    assert_includes configuration.excluded_exceptions, "ActiveRecord::RecordNotFound"
    assert_in_delta 0.05, configuration.traces_sample_rate, 0.001
  ensure
    ENV.delete("SENTRY_DSN")
    Sentry.close
  end
end
