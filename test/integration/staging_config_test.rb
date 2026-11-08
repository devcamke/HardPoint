require "test_helper"

class StagingConfigTest < ActiveSupport::TestCase
  test "the staging destination is marked as staging and keeps shops one level deeper" do
    staging = YAML.load_file(Rails.root.join("config/deploy.staging.yml"))
    env = staging.dig("env", "clear")
    assert_equal [ "staging.hardpoint.app", 2, "staging", true ], env.values_at("APP_HOST", "APP_TLD_LENGTH", "HARDPOINT_ENVIRONMENT", "ALLOW_INTEGRATION_SIMULATORS")
    assert_equal [ "staging.hardpoint.app", "*.staging.hardpoint.app" ], staging.dig("proxy", "hosts")
    assert Rails.root.join("config/backup/refresh_staging.sh").executable?
  end

  test "staging sends every email to the operators and never to the people in the data" do
    mail = Mail.new(to: [ "amina@acme.test", "bob@bolt.test" ], cc: "carl@acme.test", subject: "Your backup is ready")
    StagingMailInterceptor.delivering_email(mail)

    assert_equal [ "support@hardpoint.app" ], mail.to
    assert_nil mail.cc
    assert_equal "[staging, for amina@acme.test, bob@bolt.test, carl@acme.test] Your backup is ready", mail.subject
  end

  test "anonymising refuses to run anywhere but staging, and scrambles the people when it does" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("staging:anonymise")
    task = Rake::Task["staging:anonymise"]

    capture_io { assert_raises(SystemExit) { task.execute } }

    Rails.configuration.x.staging = true
    ENV["STAGING_PASSWORD"] = "staging-only-password"
    Account.without_isolation do
      Current.set(account: accounts(:acme), user: users(:amina)) do
        accounts(:acme).api_keys.create!(name: "Web shop", scope: "read")
        accounts(:acme).mpesa_shortcodes.create!(name: "Paybill", shortcode: "174379", environment: "simulator")
      end
    end
    capture_io { task.execute }

    Account.without_isolation do
      contractor = customers(:acme_contractor).reload
      assert_equal "Customer #{contractor.id}", contractor.name
      assert_match(/\A2547\d{8}\z/, contractor.phone)
      assert_nil contractor.tax_pin
      assert_equal "staff-#{users(:carl).id}@staging.hardpoint.test", users(:carl).reload.email_address
      assert users(:carl).authenticate("staging-only-password")
      assert_equal "ada@hardpoint.test", users(:ada).reload.email_address, "platform admins keep their logins"
      assert_nil users(:ada).two_factor_secret
      assert_equal 0, ApiKey.count
      assert_equal [ "simulator" ], Mpesa::Shortcode.distinct.pluck(:environment)
      assert_equal [ false ], Account.distinct.pluck(:sms_enabled)
    end
  ensure
    Rails.configuration.x.staging = false
    ENV.delete("STAGING_PASSWORD")
  end
end
