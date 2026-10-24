class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  # For scheduled jobs: a run still going when the next is due (a slow provider, a big night) isn't
  # joined by a second one doing the same work; the next run is dropped, and the one after picks up
  # whatever is left. Solid Queue holds the lock for at most `duration` in case a worker dies.
  def self.one_at_a_time(duration: 1.hour)
    limits_concurrency key: "scheduled", on_conflict: :discard, duration: duration
  end
end
