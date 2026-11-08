# Every few minutes, sends what's still waiting for KRA (the network was down, KRA was busy),
# with growing gaps between attempts. Refused submissions wait for someone to press Retry.
class Etims::RetryJob < ApplicationJob
  one_at_a_time(duration: 30.minutes)

  def perform
    # Only the shops with something waiting, and only the submissions whose gap has passed, chosen in SQL.
    waiting = Account.without_isolation { Etims::Submission.due_for_retry.distinct.pluck(:account_id) }
    Account.where(id: waiting).find_each do |account|
      Current.set(account: account) do
        account.etims_submissions.due_for_retry.order(:id).each(&:transmit)
      end
    end
  end
end
