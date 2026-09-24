# Every few minutes, sends what's still waiting for KRA (the network was down, KRA was busy),
# with growing gaps between attempts. Refused submissions wait for someone to press Retry.
class Etims::RetryJob < ApplicationJob
  def perform
    Account.find_each do |account|
      Current.set(account: account) do
        account.etims_submissions.pending.order(:id).select(&:due_for_retry?).each(&:transmit)
      end
    end
  end
end
