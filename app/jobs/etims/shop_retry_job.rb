# One shop's submissions that are due another try, oldest first. Not queued twice for a shop: if the last one is
# still sending (KRA is slow), the next run's is dropped.
class Etims::ShopRetryJob < ApplicationJob
  limits_concurrency key: ->(account) { account.id }, on_conflict: :discard, duration: 30.minutes

  def perform(account)
    account.etims_submissions.pending.order(:id).select(&:due_for_retry?).each(&:transmit)
  end
end
