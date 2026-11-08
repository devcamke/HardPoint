require "test_helper"

# Deploys can't be exercised here, so the shape of the deploy is checked: migrations run once per deploy from
# the hook, containers don't migrate as they boot, and the alerting and health pieces are wired up.
class DeployConfigTest < ActiveSupport::TestCase
  test "containers don't migrate as they boot; the pre-deploy hook does, once, with the new version" do
    entrypoint = Rails.root.join("bin/docker-entrypoint").read
    assert_includes entrypoint, "db:prepare:if_empty"
    assert_includes entrypoint, %(if [ "${MIGRATE_ON_BOOT:-false}" == "true" ])
    assert_equal 1, entrypoint.scan(/^\s*\.\/bin\/rails db:prepare$/).size, "a full db:prepare only behind MIGRATE_ON_BOOT"

    hook = Rails.root.join(".kamal/hooks/pre-deploy")
    assert hook.executable?, "the hook must be executable for Kamal to run it"
    assert_includes hook.read, %(app exec --primary --version "$KAMAL_VERSION")
    assert_includes hook.read, "bin/rails db:migrate"
    assert_includes hook.read, "setup|rollback) exit 0"
  end

  test "strong_migrations starts after the migrations written before it" do
    newest = Dir[Rails.root.join("db/migrate/*.rb")].map { File.basename(_1).to_i }.max
    assert_operator StrongMigrations.start_after, :<=, newest
    assert_equal 18, StrongMigrations.target_version
  end

  test "the platform checks run every 10 minutes and /health is reachable on any host without a redirect" do
    recurring = YAML.load_file(Rails.root.join("config/recurring.yml"))
    assert_equal({ "class" => "PlatformHealthJob", "schedule" => "every 10 minutes" }, recurring.dig("production", "platform_health"))
    assert_equal({ "class" => "IntegrityCheckJob", "schedule" => "every day at 1:30am" }, recurring.dig("production", "integrity_check"))

    production = Rails.root.join("config/environments/production.rb").read
    assert_includes production, %(exclude: ->(request) { request.path.in?(%w[ /up /health ]) } }, hsts:)
    assert_includes production, %(config.host_authorization = { exclude: ->(request) { request.path.in?(%w[ /up /health ]) } })
  end

  test "WAL is archived continuously and the backup scripts are sound" do
    postgres = Rails.root.join("config/postgres/postgresql.conf").read
    assert_match(/^archive_mode = on$/, postgres)
    assert_match(/^archive_timeout = 300$/, postgres)
    assert_match(%r{^archive_command = '.*wal_archive/%f'$}, postgres)

    %w[ config/backup/backup.sh config/backup/restore.sh config/backup/restore_pitr.sh config/backup/wal_ship.sh
        config/backup/refresh_staging.sh config/postgres/promote_replica.sh bin/docker-entrypoint .kamal/hooks/pre-deploy ].each do |script|
      path = Rails.root.join(script)
      assert path.executable?, "#{script} must be executable"
      assert system("bash", "-n", path.to_s), "#{script} has a syntax error"
    end
    assert_includes Rails.root.join("config/backup/backup.sh").read, "base) backup_base ;;"
  end

  test "CI scans the base image, checks accessibility, and the load test can be run against staging" do
    ci = YAML.load_file(Rails.root.join(".github/workflows/ci.yml"))
    scan = ci.dig("jobs", "scan_image", "steps").find { _1["uses"].to_s.start_with?("aquasecurity/trivy-action") }
    assert_equal [ "HIGH,CRITICAL", "1" ], [ scan.dig("with", "severity"), scan.dig("with", "exit-code") ]
    accessibility = ci.dig("jobs", "accessibility", "steps").map { _1["run"].to_s }.join
    assert_includes accessibility, "node script/accessibility_check.mjs"
    assert_includes accessibility, "db:seed:replant"

    load_test = YAML.load_file(Rails.root.join(".github/workflows/load-test.yml"))
    assert_equal "https://loadtest.staging.hardpoint.app", load_test.dig(true, "workflow_dispatch", "inputs", "base", "default")
    assert_includes Rails.root.join("perf/till.js").read, %(hosts: BASE.includes("localhost"))
    assert_includes Rails.root.join("perf/setup.rb").read, "Rails.configuration.x.staging"
  end

  test "errors go to Sentry when it's configured, and to the operators' inbox otherwise" do
    assert_equal "support@hardpoint.app", Rails.configuration.x.alerts[:email]
    assert_not Rails.configuration.x.alerts[:sentry]
    assert_includes Rails.root.join("config/initializers/error_reporting.rb").read, "Rails.error.subscribe(Alerts::ErrorSubscriber.new)"
    assert_includes Rails.root.join("config/initializers/sentry.rb").read, "config.send_default_pii = false"
  end
end
