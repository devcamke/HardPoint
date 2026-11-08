# Whether the platform is working, as one answer for the uptime monitor (/health) and the admin Database
# page, and as the checks PlatformHealthJob alerts on every ten minutes: the database and its replica, the
# job workers, jobs stuck or failed, KRA eTIMS queues that have stopped moving, shops' backups and disk space.
# Each check is :ok, :warning or :failing; only :failing takes the platform down for the monitor.
class PlatformHealth
  Check = Data.define(:name, :status, :detail) do
    def ok? = status == :ok
    def failing? = status == :failing
  end

  STUCK_JOBS_AFTER = 15.minutes
  FAILED_JOBS_WITHIN = 1.hour
  WORKER_HEARTBEAT_WITHIN = 5.minutes
  ETIMS_BACKLOG_AFTER = 2.hours
  REPLICA_LAG_LIMIT = 60 # seconds
  DISK_WARNING, DISK_FAILING = 80, 90 # percent used

  def self.check = new.tap(&:checks)

  def checks
    @checks ||= %i[ database replica queue stuck_jobs failed_jobs etims backups disk ].filter_map { run(_1) }
  end

  def ok? = checks.none?(&:failing?)
  def failing = checks.select(&:failing?)
  def status = ok? ? (checks.all?(&:ok?) ? "ok" : "warning") : "failing"

  def as_json(detail: true)
    { status: status, checked_at: Time.current.utc.iso8601,
      checks: checks.to_h { [ _1.name, detail ? { status: _1.status, detail: _1.detail } : _1.status ] } }
  end

  private
    # A check that itself blows up is a failing check, with the error, never a crash of the whole report.
    def run(name)
      send(name)
    rescue => error
      Check.new(name, :failing, "#{error.class}: #{error.message.to_s.truncate(200)}")
    end

    def database
      ActiveRecord::Base.connection.select_value("SELECT 1")
      Check.new(:database, :ok, "primary answers")
    end

    def replica
      replica = DatabaseHealth.new.replica
      return Check.new(:replica, :ok, "reads from the primary") unless replica.separate
      return Check.new(:replica, :failing, "unreachable: #{replica.error}") if replica.error
      return Check.new(:replica, :failing, "not replicating") unless replica.streaming
      return Check.new(:replica, :warning, "#{replica.lag_seconds.round} s behind") if replica.lag_seconds.to_f > REPLICA_LAG_LIMIT

      Check.new(:replica, :ok, "streaming, #{replica.lag_seconds.to_f.round(1)} s behind")
    end

    # Solid Queue only runs in production; in development and test the adapter is something else.
    def solid_queue? = ActiveJob::Base.queue_adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)

    def queue
      return unless solid_queue?

      alive = SolidQueue::Process.where(last_heartbeat_at: WORKER_HEARTBEAT_WITHIN.ago..).group(:kind).count
      return Check.new(:queue, :failing, "no worker has sent a heartbeat in #{WORKER_HEARTBEAT_WITHIN.inspect}") if alive["Worker"].to_i.zero?
      return Check.new(:queue, :failing, "no dispatcher: scheduled jobs and retries won't run") if alive["Dispatcher"].to_i.zero?
      return Check.new(:queue, :warning, "no scheduler: recurring tasks (billing, eTIMS retries) won't start") if alive["Scheduler"].to_i.zero?

      Check.new(:queue, :ok, alive.map { "#{_2} #{_1.downcase.pluralize(_2)}" }.sort.join(", "))
    end

    def stuck_jobs
      return unless solid_queue?

      waiting = SolidQueue::ReadyExecution.where(created_at: ..STUCK_JOBS_AFTER.ago).count
      waiting.zero? ? Check.new(:stuck_jobs, :ok, "nothing waiting for more than #{STUCK_JOBS_AFTER.inspect}")
                    : Check.new(:stuck_jobs, :failing, "#{waiting} jobs have waited more than #{STUCK_JOBS_AFTER.inspect}")
    end

    def failed_jobs
      return unless solid_queue?

      failed = SolidQueue::FailedExecution.where(created_at: FAILED_JOBS_WITHIN.ago..).includes(:job).to_a
      return Check.new(:failed_jobs, :ok, "none in the last hour") if failed.empty?

      Check.new(:failed_jobs, :failing, "#{failed.size} in the last hour: #{failed.map { _1.job&.class_name }.compact.tally.map { "#{_1} ×#{_2}" }.join(", ")}")
    end

    # eTIMS retries by itself while KRA is down; a sale still unsigned after two hours needs looking at.
    def etims
      late = Account.without_isolation { Etims::Submission.pending.where(created_at: ..ETIMS_BACKLOG_AFTER.ago).distinct.count(:account_id) }
      late.zero? ? Check.new(:etims, :ok, "no sale has waited more than #{ETIMS_BACKLOG_AFTER.inspect} for KRA")
                 : Check.new(:etims, :warning, "#{late} #{"shop".pluralize(late)} with sales waiting more than #{ETIMS_BACKLOG_AFTER.inspect} for KRA")
    end

    def backups
      failed, stuck = Account.without_isolation do
        [ AccountBackup.failed.where(created_at: 1.day.ago..).count, AccountBackup.in_progress.where(created_at: ..3.hours.ago).count ]
      end
      return Check.new(:backups, :failing, "#{failed} shop backups failed in the last day") if failed.positive?
      return Check.new(:backups, :warning, "#{stuck} shop backups have been running for more than 3 hours") if stuck.positive?

      Check.new(:backups, :ok, "no shop backup failed in the last day")
    end

    # Where uploads and scratch files go (the Kamal storage volume in production).
    def disk
      output = IO.popen([ "df", "-Pk", Rails.root.join("storage").to_s ], &:read)
      used = output.to_s.lines.last.to_s.split[4].to_s.delete("%").to_i
      return Check.new(:disk, :failing, "#{used}% used") if used >= DISK_FAILING
      return Check.new(:disk, :warning, "#{used}% used") if used >= DISK_WARNING

      Check.new(:disk, :ok, "#{used}% used")
    end
end
