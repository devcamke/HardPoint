# Every hour, finds sales, voids and returns at branches with a control unit that were never queued for
# KRA (the app stopped between saving one and queuing it) and queues them. The last few minutes are left
# alone, as they're still on their way; so is anything from before the control unit was last switched
# on, so sales made while it was off aren't sent when it's switched back on.
class Etims::ReconcileJob < ApplicationJob
  one_at_a_time(duration: 30.minutes)

  LOOK_BACK = 7.days
  SETTLE = 10.minutes

  def perform
    Account.find_each do |account|
      Current.set(account: account) do
        account.etims_devices.active.each { queue_missing(account, _1) }
      end
    end
  end

  private
    def queue_missing(account, device)
      window = [ switched_on_at(device), LOOK_BACK.ago ].max..SETTLE.ago
      return if window.begin > window.end

      sales = account.sales.where(branch: device.branch)
      queued = ->(type, kind) { account.etims_submissions.where(document_type: type, kind: kind).select(:document_id) }

      sales.finished.where(completed_at: window).where.not(id: queued.("Sale", "sale")).order(:completed_at, :id)
        .each { Etims::Submission.queue(_1, kind: "sale") }
      sales.voided.where(voided_at: window).where.not(id: queued.("Sale", "credit_note")).order(:voided_at, :id)
        .each { Etims::Submission.queue(_1, kind: "credit_note") }
      account.sale_returns.where(branch: device.branch, created_at: window).where.not(id: queued.("SaleReturn", "credit_note")).order(:id)
        .each { Etims::Submission.queue(_1, kind: "credit_note") }
    end

    # When the control unit was added, or last switched back on after being off. Other edits to it (a new item
    # class, say) don't move this, so they don't hide anything lost before them.
    def switched_on_at(device)
      device.events.where(action: "updated").where("events.particulars -> 'changes' -> 'active' ->> 1 = 'true'").maximum(:created_at) ||
        device.created_at
    end
end
