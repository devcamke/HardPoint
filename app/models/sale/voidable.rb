module Sale::Voidable
  extend ActiveSupport::Concern

  # A completed sale can be voided while its shift is still open (a mistake caught at the till);
  # later on, it's a return. Stock goes back and the payments no longer count.
  def voidable?
    completed? && shift.open? && sale_returns.none?
  end

  def void(reason:, by: Current.user, approver: by)
    with_lock do
      return false unless voidable?

      lines.each(&:restore_stock)
      update! status: :voided, voided_by: by, voided_at: Time.current, void_reason: reason
      customer_order&.reopen
      track_event "voided", creator: by, reason: reason, approver: approver.name, total: total_cents
    end
  end

  # An unfinished cart that's no longer wanted. It never took stock or money.
  def discard
    (open? || parked?) && payments.none? && destroy
  end

  def park
    open? && lines.any? && update(status: :parked)
  end

  def recall
    parked? && !shift.sales.open.where.not(id: id).joins(:lines).exists? && begin
      shift.sales.open.where.not(id: id).destroy_all
      update(status: :open)
    end
  end
end
