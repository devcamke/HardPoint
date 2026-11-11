# Every few minutes, sends what's still waiting for KRA (the network was down, KRA was busy),
# with growing gaps between attempts. Refused submissions wait for someone to press Retry.
#
# Only shops with something waiting are looked at, and each is sent in its own job (Etims::ShopRetryJob), so the
# workers send for several shops at once and one whose connection to KRA hangs doesn't hold up the rest.
class Etims::RetryJob < ApplicationJob
  one_at_a_time(duration: 30.minutes)

  def perform
    waiting = Account.without_isolation { Etims::Submission.pending.distinct.pluck(:account_id) }
    Account.where(id: waiting).find_each do |account|
      Current.set(account: account) { Etims::ShopRetryJob.perform_later(account) }
    end
  end
end
