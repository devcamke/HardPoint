require "test_helper"

# The production and scaled-out settings can't be exercised here, so their shape is checked.
class ScalingConfigTest < ActiveSupport::TestCase
  test "production has a replica, on its own host when DATABASE_REPLICA_HOST is set" do
    config = ActiveRecord::DatabaseConfigurations.new(YAML.load(ERB.new(File.read(Rails.root.join("config/database.yml"))).result, aliases: true))
    replica = config.configs_for(env_name: "production", name: "primary_replica", include_hidden: true)
    assert replica.replica?
    assert_equal "hardpoint_production", replica.database

    with_env("DATABASE_REPLICA_HOST" => "10.0.0.22") do
      config = ActiveRecord::DatabaseConfigurations.new(YAML.load(ERB.new(File.read(Rails.root.join("config/database.yml"))).result, aliases: true))
      assert_equal "10.0.0.22", config.configs_for(env_name: "production", name: "primary_replica", include_hidden: true).host
    end
  end

  test "the scaled destination runs jobs on their own server and keeps uploads in object storage" do
    scaled = YAML.load_file(Rails.root.join("config/deploy.scaled.yml"))
    assert_equal "bin/jobs", scaled.dig("servers", "job", "cmd")
    assert_equal false, scaled.dig("env", "clear", "SOLID_QUEUE_IN_PUMA")
    assert_equal "object_storage", scaled.dig("env", "clear", "ACTIVE_STORAGE_SERVICE")
    assert scaled.dig("env", "clear", "DATABASE_REPLICA_HOST")
    assert_includes Rails.root.join("config/puma.rb").read, %(%w[ true 1 ].include?(ENV["SOLID_QUEUE_IN_PUMA"])), "\"false\" mustn't start jobs in Puma"
    assert_includes YAML.load(ERB.new(Rails.root.join("config/storage.yml").read).result).keys, "object_storage"
  end

  private
    def with_env(values)
      previous = values.keys.index_with { ENV[_1] }
      values.each { ENV[_1] = _2 }
      yield
    ensure
      previous.each { ENV[_1] = _2 }
    end
end
