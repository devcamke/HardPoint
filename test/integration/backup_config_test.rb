require "test_helper"

# The continuous-backup pieces live in different files (Postgres' config, the WAL-G wrapper, Kamal's
# mounts, the host scripts). If they drift apart, archiving silently stops, so they're checked here.
class BackupConfigTest < ActiveSupport::TestCase
  def deploy(name = "deploy") = YAML.load_file(Rails.root.join("config/#{name}.yml"))
  def postgresql_conf = Rails.root.join("config/postgres/postgresql.conf").read
  def wrapper = Rails.root.join("config/postgres/wal-g.sh").read

  test "Postgres archives through the wrapper that Kamal mounts, with WAL-G and its settings beside it" do
    assert_match(/^archive_mode = on$/, postgresql_conf)
    command = postgresql_conf[/^archive_command = '(.+)'$/, 1]
    wrapper_path = command[%r{(/\S+hardpoint-wal-g)}, 1]
    assert wrapper_path, "archive_command should call the wrapper"
    assert_match(/^archive_timeout = \d+$/, postgresql_conf)

    [ deploy["accessories"]["db"], deploy("deploy.scaled")["accessories"]["db-replica"] ].each do |accessory|
      assert_includes accessory["files"], "config/postgres/wal-g.sh:#{wrapper_path}"
      assert_includes accessory["volumes"], "/opt/hardpoint/wal-g:#{File.dirname(wrapper[/WALG_BIN:-(\S+)\}/, 1])}:ro"
      assert_includes accessory["volumes"], "/etc/hardpoint/wal-g:#{File.dirname(wrapper[/WALG_ENV_FILE:-(\S+)\}/, 1])}:ro"
    end
  end

  test "WAL-G is a pinned release checked against its checksum" do
    script = Rails.root.join("config/backup/install_walg.sh").read
    assert_match(/WALG_VERSION:-v\d+\.\d+\.\d+\}/, script)
    assert_match(/WALG_SHA256:-\h{64}\}/, script)
    assert_match "sha256sum --check", script
  end

  test "the backup scripts parse" do
    Dir[Rails.root.join("config/{backup,postgres}/*.sh")].each do |script|
      assert system("bash", "-n", script), "#{script} has a syntax error"
    end
  end
end
