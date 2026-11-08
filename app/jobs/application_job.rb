class ApplicationJob < ActiveJob::Base
  # A job that gives up, because it raised something it doesn't retry or ran out of retries, is reported
  # (Sentry, or an email to the operators) before Solid Queue records it as failed; a retry that will be
  # tried again isn't, so a provider's bad minute doesn't page anyone.
  after_discard do |job, error|
    Rails.error.report(error, handled: true, severity: :error, source: "application.active_job",
      context: { job: job.class.name, job_id: job.job_id, executions: job.executions, account_id: Current.account&.id })
  end

  # For scheduled jobs: a run still going when the next is due (a slow provider, a big night) isn't
  # joined by a second one doing the same work; the next run is dropped, and the one after picks up
  # whatever is left. Solid Queue holds the lock for at most `duration` in case a worker dies.
  def self.one_at_a_time(duration: 1.hour)
    limits_concurrency key: "scheduled", on_conflict: :discard, duration: duration
  end
end
