# Sends one sale, void or return to KRA. A control unit takes its invoices one at a time and in the
# order they were numbered: jobs for the same unit wait their turn (Solid Queue releases them in the
# order they were queued), so two workers can't send invoice 101 before 100.
class Etims::TransmitJob < ApplicationJob
  limits_concurrency to: 1, key: ->(submission) { submission.device_id }, duration: 5.minutes

  def perform(submission)
    submission.transmit
  end
end
