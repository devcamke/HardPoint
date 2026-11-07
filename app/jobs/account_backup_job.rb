class AccountBackupJob < ApplicationJob
  queue_as :backups
  # Backups are the heaviest work HardPoint does: at most two run at once across all shops, and the
  # rest wait their turn (without holding a worker) instead of slowing the tills at 02:00.
  limits_concurrency to: 2, key: "account_backups", duration: AccountBackup::STALLED_AFTER

  # A blip in storage or the database is tried again; the last failure is reported to the owners.
  retry_on StandardError, attempts: AccountBackup::ATTEMPTS, wait: :polynomially_longer do |job, error|
    job.arguments.first.fail!(error.is_a?(AccountBackup::VerificationFailed) ? "It didn't pass its checks: #{error.message}" : "#{error.class.name}: #{error.message}")
  end
  discard_on ActiveJob::DeserializationError # the shop was deleted while its backup waited

  def perform(backup)
    backup.perform
  end
end
