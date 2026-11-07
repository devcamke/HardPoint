# A shop's own backup: a verified copy of all its data and files, taken on the schedule its owners
# choose (daily, weekly or monthly, at 02:00 in the shop's time zone) or when an owner presses
# "Back up now". Kept in the backup store (BACKUP_STORAGE_SERVICE, ideally a bucket away from the
# server); the newest few scheduled backups are kept, manual ones for 30 days. Every owner is
# emailed when one is ready (if they want that) and always when one fails.
#
# HardPoint's own hourly backups of the whole database (config/backup) are separate: those are for
# disaster recovery, these are the shop's copy of its own records.
class AccountBackup < ApplicationRecord
  class VerificationFailed < StandardError; end

  FREQUENCIES = %w[ off daily weekly monthly ].freeze
  NOTIFICATIONS = %w[ every failures ].freeze
  KEPT_RANGE = 1..30
  MANUAL_RETENTION = 30.days
  HOUR = 2 # scheduled backups start at 02:00 in the shop's time zone, when nobody's selling
  # A backup still running after this was killed with its worker (a deploy, the server restarting).
  STALLED_AFTER = 6.hours
  ATTEMPTS = 3

  belongs_to :account, default: -> { Current.account }
  belongs_to :requested_by, class_name: "User", optional: true
  has_one_attached :file, service: ENV["BACKUP_STORAGE_SERVICE"].presence&.to_sym

  enum :kind, %w[ manual scheduled ].index_by(&:itself), validate: true
  enum :status, %w[ queued running succeeded failed expired ].index_by(&:itself), default: "queued"

  scope :chronologically, -> { order(created_at: :desc, id: :desc) }
  scope :in_progress, -> { where(status: %w[ queued running ]) }

  validates :requested_by, presence: true, if: :manual?
  validate :one_at_a_time, on: :create

  after_create_commit -> { AccountBackupJob.perform_later(self) }

  class << self
    # Hourly: the scheduled backup for each shop whose period has started and doesn't have one yet.
    # The period key makes this safe to run any number of times, and a missed hour (a deploy, the
    # server down at 02:00) is caught up by the next run.
    def schedule_due(now: Time.current)
      Account.without_isolation do
        Account.where.not(backup_frequency: "off").find_each do |account|
          period = period_for(account, now)
          next if period.nil? || account.account_backups.exists?(period: period)

          Current.set(account: account) { account.account_backups.create!(kind: "scheduled", period: period) }
        rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
          next # another run got there first, or the owner's own backup is still going; the next hour tries again
        end
      end
    end

    # "daily:2026-11-07", "weekly:2026-W45" or "monthly:2026-11" once that period's 02:00 has passed
    # in the shop's time zone; nil before then.
    def period_for(account, now = Time.current)
      local = now.in_time_zone(account.time_zone)
      return if local.hour < HOUR && starts_period?(account.backup_frequency, local.to_date)

      date = local.to_date
      case account.backup_frequency
      when "daily" then "daily:#{date.iso8601}"
      when "weekly" then "weekly:#{date.cwyear}-W#{date.cweek.to_s.rjust(2, "0")}"
      when "monthly" then "monthly:#{date.strftime("%Y-%m")}"
      end
    end

    # Nightly: removes backups past their time, and fails ones whose worker died mid-way.
    def maintain
      Account.without_isolation do
        where(status: "running", started_at: ..STALLED_AFTER.ago)
          .or(where(status: "queued", created_at: ..1.day.ago)).includes(:account).find_each do |backup|
          Current.set(account: backup.account) { backup.fail!("It stopped part-way through (the server restarted)") }
        end

        succeeded.where(expires_at: ..Time.current).includes(:account).find_each do |backup|
          Current.set(account: backup.account) { backup.expire! }
        end
      end
    end

    private
      def starts_period?(frequency, date)
        frequency == "daily" || (frequency == "weekly" && date.cwday == 1) || (frequency == "monthly" && date.day == 1)
      end
  end

  # Called by AccountBackupJob. A job run again for a backup that's already done does nothing.
  def perform
    return unless queued? || running?

    update!(status: "running", started_at: Time.current, attempts: attempts + 1, failure: nil)
    Tempfile.create([ "backup", ".zip" ], binmode: true) do |zip|
      # A heavy read, so from the replica when there is one.
      manifest = Account.reading { AccountBackup::Archive.new(account).write(zip.path) }
      verify_archive! zip.path, manifest
      store zip.path, manifest
    end
    prune
    notify :succeeded
  end

  # The last attempt failed (or the job died): tell the owners, and the platform's error tracker.
  def fail!(reason)
    file.purge if file.attached?
    update!(status: "failed", finished_at: Time.current, failure: reason.to_s.first(250))
    Rails.error.report(RuntimeError.new("Backup #{id} of #{account.subdomain} failed: #{failure}"), handled: true, severity: :error)
    account.track_event "backup_failed", creator: nil, kind: kind
    AccountBackupsMailer.with(backup: self).failed_for_support.deliver_later
    notify :failed
  end

  def expire!
    file.purge
    update!(status: "expired")
  end

  def filename
    "hardpoint-#{account.subdomain}-backup-#{created_at.in_time_zone(account.time_zone).strftime("%Y-%m-%d-%H%M")}.zip"
  end

  def downloadable?
    succeeded? && file.attached?
  end

  def duration
    finished_at - started_at if finished_at && started_at
  end

  def table_count = manifest.fetch("tables", {}).size
  def row_count = manifest.fetch("tables", {}).values.sum
  def file_count = manifest.fetch("files", {}).count { |name, _| name.start_with?("files/") }

  private
    def one_at_a_time
      errors.add :base, "A backup is already being made" if account.account_backups.in_progress.exists?
    end

    # Every file in the ZIP is read back and checked against the manifest before it's kept.
    def verify_archive!(path, manifest)
      expected = manifest.fetch("files")
      Zip::File.open(path) do |zip|
        names = zip.entries.map(&:name) - [ AccountBackup::Archive::MANIFEST ]
        raise VerificationFailed, "the ZIP's files don't match its manifest" unless names.sort == expected.keys.sort

        zip.each do |entry|
          next if entry.name == AccountBackup::Archive::MANIFEST

          digest = Digest::SHA256.new
          entry.get_input_stream { |io| while (chunk = io.read(1.megabyte)) do digest << chunk end }
          raise VerificationFailed, "#{entry.name} doesn't match its checksum" unless digest.hexdigest == expected[entry.name]
        end
      end
    end

    # Uploads the ZIP, then downloads it again and compares checksums, so a backup is only marked
    # good once the stored copy is known to be good.
    def store(path, manifest)
      checksum = Digest::SHA256.file(path).hexdigest
      file.attach(io: File.open(path), filename: filename, content_type: "application/zip")
      stored = Digest::SHA256.new
      file.blob.download { |chunk| stored << chunk }
      raise VerificationFailed, "the stored copy doesn't match the original" unless stored.hexdigest == checksum

      update!(status: "succeeded", finished_at: Time.current, byte_size: File.size(path), checksum: checksum, manifest: manifest,
        expires_at: (MANUAL_RETENTION.from_now if manual?))
    end

    # Keeps the newest scheduled backups the owners asked for. The newest good backup of any kind
    # is never removed.
    def prune
      kept = account.account_backups.succeeded.scheduled.chronologically.limit(account.backups_kept).pluck(:id)
      account.account_backups.succeeded.scheduled.where.not(id: kept + [ id ]).find_each(&:expire!)
    end

    def notify(outcome)
      return if outcome == :succeeded && account.backup_notifications == "failures"

      account.users.where(memberships: { role: "owner" }).find_each do |owner|
        AccountBackupsMailer.with(backup: self, recipient: owner).public_send(outcome).deliver_later
      end
    end
end
