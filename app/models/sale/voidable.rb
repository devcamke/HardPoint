module Sale::Voidable
  extend ActiveSupport::Concern

  # How the money went back on a void, in words for the sale, Activity and the till.
  REFUND_WORDS = { "cash" => "in cash", "card" => "to the card", "mobile_money" => "by M-Pesa", "airtel_money" => "by Airtel Money",
                   "on_account" => "to the customer's account" }.freeze

  def self.refund_words(method, reference = nil)
    return if method.blank?

    "refunded #{REFUND_WORDS.fetch(method, method.humanize.downcase)}#{" (#{reference})" if reference.present?}"
  end

  # A completed sale can be voided while its shift is still open (a mistake caught at the till);
  # later on, it's a return. Stock goes back and the payments no longer count.
  def voidable?
    completed? && shift.open? && sale_returns.none?
  end

  # The money goes back some way, and the void says which: cash comes out of the shift's drawer and counts against
  # it; an M-Pesa or Airtel Money reversal carries its code, and the money Safaricom sent is marked refunded so
  # reconciliation can tell it from money used on a sale; a card refund may carry a code; on account there's
  # nothing to hand back, since the sale no longer counts towards what the customer owes. Left unsaid, the money
  # goes back the way it came, when the sale was paid one way.
  def void(reason:, by: Current.user, approver: by, refund_method: nil, refund_reference: nil)
    with_lock do
      return false unless voidable?

      refund_method = refund_method.presence || default_void_refund_method
      errors.clear
      if refundable_payments.any? && !refund_method.in?(SaleReturn::REFUND_METHODS)
        errors.add :base, "Say how the #{Money.format(money_paid_cents)} paid went back"
      elsif refund_method.in?(%w[ mobile_money airtel_money ]) && refund_reference.blank?
        errors.add :base, "Enter the #{refund_method == "mobile_money" ? "M-Pesa" : "Airtel Money"} reversal code"
      elsif refund_method == "on_account" && customer.nil?
        errors.add :base, "This sale has no customer whose account could be credited"
      end
      return false if errors.any?

      lines.each(&:restore_stock)
      update! status: :voided, voided_by: by, voided_at: Time.current, void_reason: reason,
        void_refund_method: (refund_method if refundable_payments.any?), void_refund_reference: refund_reference.to_s.strip.upcase.presence,
        void_refund_cents: (money_paid_cents if refundable_payments.any?)
      # Only an M-Pesa reversal sends Safaricom's money back; M-Pesa refunded in cash is still money received.
      account.mpesa_transactions.where(matched: payments.select(&:mobile_money?)).update_all(refunded_at: Time.current) if void_refund_method == "mobile_money"
      customer_order&.reopen(self)
      reverse_fundi_commission(by: by)
      track_event "voided", creator: by, reason: reason, approver: approver, total: total_cents,
        refund_method: void_refund_method, refund_reference: void_refund_reference
      account.alert_owners(:large_void, self, by: by) if total_cents > account.alert_void_above_cents
      true
    end
  end

  # The one way the sale was paid, foreign notes counting as cash. A sale paid two ways has to be told.
  def default_void_refund_method
    tenders = refundable_payments.map { _1.foreign_cash? ? "cash" : _1.tender }.uniq
    tenders.first if tenders.one?
  end

  # The money that goes back on a void: what was paid in money. A deposit goes back to its order, and the part
  # put on account stops counting towards what the customer owes, so neither is handed back. The void keeps it
  # (void_refund_cents).
  def money_paid_cents
    refundable_payments.sum(&:amount_cents)
  end

  # What a void handed back. Voids from before it was kept handed back the sale's whole total.
  def void_refunded_cents
    void_refund_cents || total_cents
  end

  def void_refund_words
    Sale::Voidable.refund_words(void_refund_method, void_refund_reference)
  end

  # An unfinished cart that's no longer wanted. It never took stock or money, and no money is on its way to it:
  # a prompt the customer may yet answer would arrive to find nothing to pay, and the money would be lost.
  def discard
    return false unless open? || parked?

    errors.clear
    if payments.any?
      errors.add :base, "Remove the payments before clearing this sale"
    elsif stk_requests.pending.exists? || airtel_requests.pending.exists?
      errors.add :base, "A payment prompt is still waiting for the customer's answer. Cancel it, or wait for it, before clearing this sale"
    end
    errors.none? && destroy
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

  private
    # A deposit used on the sale goes back to its order when the order is reopened, and what was put on account
    # stops counting towards the customer's debt, so there's nothing to hand back for either.
    def refundable_payments
      payments.reject { _1.deposit? || _1.points? || _1.on_account? }
    end
end
