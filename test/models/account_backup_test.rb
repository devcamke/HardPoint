require "test_helper"

class AccountBackupTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper, ActiveJob::TestHelper

  setup do
    @account = accounts(:acme)
    Current.account = @account
    Current.session = @account.sessions.create!(user: users(:amina))
  end

  def owner_emails = @account.users.where(memberships: { role: "owner" }).pluck(:email_address)

  def entries(backup)
    files = {}
    Zip::File.open_buffer(StringIO.new(backup.file.download)) { |zip| zip.each { files[_1.name] = _1.get_input_stream.read } }
    files
  end

  # Replaces obj.name for the block (no mocking library here).
  def replacing(object, name, implementation)
    original = object.method(name)
    object.define_singleton_method(name, &implementation)
    yield
  ensure
    object.singleton_class.send(:remove_method, name)
    object.define_singleton_method(name, original) unless object.respond_to?(name)
  end

  def backup!(**attributes)
    @account.account_backups.create!(kind: "manual", requested_by: users(:amina), **attributes)
  end

  test "a verified ZIP of the shop's data with a manifest of checksums and row counts" do
    backup = backup!
    backup.perform

    assert backup.succeeded?
    assert_equal backup.file.download.then { Digest::SHA256.hexdigest(_1) }, backup.checksum
    assert_in_delta 30.days.from_now, backup.expires_at, 1.minute

    files = entries(backup)
    manifest = JSON.parse(files.fetch("manifest.json"))
    assert_equal @account.products.count, manifest["tables"]["products"]
    assert_equal @account.subdomain, manifest["shop"]["subdomain"]
    (files.keys - [ "manifest.json" ]).each do |name|
      assert_equal Digest::SHA256.hexdigest(files[name]), manifest["files"].fetch(name), name
    end

    products = CSV.parse(files.fetch("data/products.csv"), headers: true)
    assert_not_includes products.map { _1["sku"] }, products(:bolt_hammer).sku
    assert_not files.key?("data/sessions.csv")
    assert_not files.key?("data/account_backups.csv")
    assert_match "manifest.json", files.fetch("README.txt")
  end

  test "every owner is emailed when it's ready, unless they only want failures" do
    assert_enqueued_emails(owner_emails.size) { backup!.perform }
    assert_operator owner_emails.size, :>=, 1

    @account.update!(backup_notifications: "failures")
    assert_no_enqueued_emails { backup!.perform }
  end

  test "only one backup at a time" do
    backup!
    second = @account.account_backups.new(kind: "manual", requested_by: users(:amina))
    assert_not second.save
    assert_match "already", second.errors.full_messages.to_sentence
  end

  test "a backup that keeps failing is marked failed, and owners and support are emailed" do
    backup = backup!
    replacing(AccountBackup::Archive, :new, ->(*) { raise IOError, "disk full" }) do
      assert_raises(IOError) { backup.perform }
      assert backup.reload.running?
      assert_equal 1, backup.attempts

      owners = owner_emails.size
      assert_emails(owners + 1) do
        perform_enqueued_jobs { AccountBackupJob.perform_later(backup) }
      end
    end

    Current.account = @account # running jobs resets Current
    backup.reload
    assert backup.failed?
    assert_equal AccountBackup::ATTEMPTS + 1, backup.attempts
    assert_match "disk full", backup.failure
    assert_not backup.file.attached?
    assert_equal "backup_failed", @account.account_events.last.action
  end

  test "a ZIP that doesn't match its manifest is never kept" do
    backup = backup!
    replacing(backup, :store, ->(*) { flunk "stored a bad backup" }) do
      replacing(Zip::File, :open, ->(*) { raise AccountBackup::VerificationFailed, "corrupt" }) do
        assert_raises(AccountBackup::VerificationFailed) { backup.perform }
      end
    end
    assert_not backup.reload.succeeded?
  end

  test "finished backups aren't done again" do
    backup = backup!
    backup.perform
    checksum = backup.checksum
    assert_no_changes -> { backup.reload.updated_at } do
      backup.perform
    end
    assert_equal checksum, backup.checksum
  end

  test "the scheduled period starts at 02:00 in the shop's time zone" do
    @account.update!(time_zone: "Nairobi", backup_frequency: "daily")
    assert_nil AccountBackup.period_for(@account, Time.utc(2026, 11, 6, 22, 30))  # 01:30 in Nairobi
    assert_equal "daily:2026-11-07", AccountBackup.period_for(@account, Time.utc(2026, 11, 6, 23, 30))

    @account.backup_frequency = "weekly"
    assert_nil AccountBackup.period_for(@account, Time.utc(2026, 11, 8, 22, 0)) # Monday 01:00
    assert_equal "weekly:2026-W46", AccountBackup.period_for(@account, Time.utc(2026, 11, 9, 0, 0))
    assert_equal "weekly:2026-W45", AccountBackup.period_for(@account, Time.utc(2026, 11, 7, 12, 0)) # caught up mid-week

    @account.backup_frequency = "monthly"
    assert_equal "monthly:2026-11", AccountBackup.period_for(@account, Time.utc(2026, 11, 7, 12, 0))

    @account.backup_frequency = "off"
    assert_nil AccountBackup.period_for(@account, Time.utc(2026, 11, 7, 12, 0))
  end

  test "scheduling makes one backup per shop per period, however often it runs" do
    Account.without_isolation { Account.where.not(id: @account.id).update_all(backup_frequency: "off") }
    now = Time.utc(2026, 11, 7, 3, 0)

    assert_difference -> { Account.without_isolation { AccountBackup.count } }, 1 do
      assert_enqueued_jobs(1, only: AccountBackupJob) do
        2.times { AccountBackup.schedule_due(now: now) }
      end
    end
    backup = Account.without_isolation { AccountBackup.last }
    assert backup.scheduled?
    assert_equal "daily:2026-11-07", backup.period
    assert_nil backup.requested_by
  end

  test "keeps the newest scheduled backups the owners chose, and manual ones for 30 days" do
    @account.update!(backups_kept: 2)
    scheduled = 4.times.map do |day|
      travel_to(Time.utc(2026, 11, 1 + day, 3)) { @account.account_backups.create!(kind: "scheduled", period: "daily:#{day}").tap(&:perform) }
    end
    manual = backup!.tap(&:perform)

    assert_equal %w[ expired expired succeeded succeeded ], scheduled.map { _1.reload.status }
    assert_not scheduled.first.file.attached?
    assert manual.reload.succeeded?

    travel 31.days do
      AccountBackup.maintain
      assert manual.reload.expired?
      assert scheduled.last.reload.succeeded?
    end
  end

  test "a backup whose worker died is failed and reported" do
    backup = backup!
    backup.update!(status: "running", started_at: 7.hours.ago)
    owners = owner_emails.size
    Current.reset
    assert_emails(owners + 1) { perform_enqueued_jobs { AccountBackup.maintain } }
    assert Account.without_isolation { backup.reload.failed? }
  end

  test "the shop's backups go when the shop is deleted" do
    backup = backup!.tap(&:perform)
    blob_id = backup.file.blob.id
    Current.reset
    Account.without_isolation { @account.reload.purge! }
    assert_not Account.without_isolation { AccountBackup.exists?(backup.id) }
    assert_not ActiveStorage::Attachment.exists?(blob_id: blob_id)
  end
end
