# Hourly: starts each shop's scheduled backup once its day, week or month has begun (02:00 local).
class AccountBackupScheduleJob < ApplicationJob
  one_at_a_time

  def perform
    AccountBackup.schedule_due
  end
end
