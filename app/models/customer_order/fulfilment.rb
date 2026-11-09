module CustomerOrder::Fulfilment
  extend ActiveSupport::Concern

  # Confirming commits the shop's stock to the order. For a customer who buys on account, an order worth more
  # than the credit they have left needs an owner's or manager's approval (approver), as putting it on account
  # at the till would (Sale::Payable); a cash-only customer pays at the till, so there's nothing to check.
  # A deposit skips the check: the customer has put money down, and the till checks the credit again when
  # the rest goes on account.
  def confirm(approver: nil, check_credit: true)
    return false unless quote?

    if expired?
      errors.add :base, "This quote expired on #{valid_until.to_fs(:long)}. Change its date to confirm it at the same prices"
      return false
    elsif check_credit && over_credit_limit? && approver.nil?
      errors.add :base, "#{customer.name} has only #{Money.format(customer.available_credit_cents)} of credit left. " \
        "Confirming this #{Money.format(balance_to_pay_cents)} order needs a manager's approval PIN"
      return false
    end

    transaction do
      if check_credit && over_credit_limit?
        track_event "credit_approved", approver: approver, customer: customer.name, amount: balance_to_pay_cents, available: customer.available_credit_cents
      end
      update(status: :ordered, ordered_at: Time.current).tap { |confirmed| track_event "confirmed", total: total_cents if confirmed }
    end
  end

  # Whether what's still to pay on this order is more than the customer's credit allows.
  def over_credit_limit?
    customer.buys_on_account? && balance_to_pay_cents > customer.available_credit_cents
  end

  def mark_ready
    ordered? && update(status: :ready).tap { |ready| track_event "ready" if ready }
  end

  # A deposit still held has to be refunded, or kept (forfeit_deposit), before cancelling.
  def cancel(reason: nil)
    return false unless quote? || ordered? || ready?

    if deposit_balance_cents.positive?
      errors.add :base, "Refund the #{Money.format(deposit_balance_cents)} deposit first, or keep it"
      return false
    end

    update(status: :cancelled).tap { |cancelled| track_event "cancelled", reason: reason if cancelled }
  end

  # The customer isn't coming back, and the shop keeps the deposit. It's income, so it's rung through the till
  # as a sale of "Forfeited deposit" paid from the deposit itself: KRA signs it, it's in the day's takings and the
  # VAT return, and the drawer isn't touched. Then the order is cancelled. Needs a manager (the approver).
  def forfeit_deposit(shift:, approver:, reason: nil)
    errors.clear
    errors.add :base, "This #{kind.downcase} holds no deposit" unless deposit_balance_cents.positive?
    errors.add :base, "Keeping a deposit needs a manager's approval PIN" unless approver
    errors.add :base, "Keeping a deposit goes through a till with an open shift" if shift.nil? || !shift.open?
    return false if errors.any?

    transaction do
      lock!
      amount = deposit_balance_cents
      sale = shift.sales.create!(account: account, branch: shift.branch, register: shift.register, cashier: approver, customer: customer, customer_order: self)
      sale.lines.create!(account: account, product: account.forfeited_deposit_product, quantity: 1, unit_price_cents: amount, detail: "on #{reference}")
      sale.recalculate
      payment = sale.pay(tender: "deposit", amount_cents: amount)
      raise ActiveRecord::RecordInvalid, payment unless payment.persisted? && sale.reload.completed?

      track_event "deposit_kept", amount: amount, approver: approver, receipt_number: sale.receipt_number, reason: reason
      update!(status: :cancelled)
      track_event "cancelled", reason: reason.presence || "Deposit kept"
    end
    true
  rescue ActiveRecord::RecordInvalid => invalid
    errors.add :base, invalid.record.errors.full_messages.to_sentence
    false
  end

  def takes_deposits?
    quote? || ordered? || ready?
  end

  class_methods do
    # { order id => deposit balance } for a page of orders, in two queries rather than two per order.
    def deposit_balances_by_id(ids)
      paid = Deposit.where(customer_order_id: ids).group(:customer_order_id).sum(:amount_cents)
      used = Payment.deposit.joins(:sale).where(sales: { customer_order_id: ids, status: "completed" }).group("sales.customer_order_id").sum(:amount_cents)
      ids.index_with { paid[_1].to_i - used[_1].to_i }
    end
  end

  # Set when worked out for a list of orders at once.
  attr_writer :deposit_balance_cents

  # Deposits paid, less refunds, less what's been used towards the sale that collected the order.
  def deposit_balance_cents
    @deposit_balance_cents || (deposits.sum(:amount_cents) - Payment.deposit.joins(:sale).where(sales: { customer_order_id: id, status: "completed" }).sum(:amount_cents))
  end

  def deposits_paid_cents
    deposits.sum(:amount_cents)
  end

  def balance_to_pay_cents
    total_cents - deposit_balance_cents
  end

  # Taking a deposit confirms a quote: the customer has committed.
  def take_deposit(amount_cents:, tender:, reference: nil, shift: nil)
    deposit = deposits.build(account: account, amount_cents: amount_cents, tender: tender, reference: reference.presence, shift: shift)
    deposit.errors.add :base, "This #{kind.downcase} can't take a deposit" unless takes_deposits?
    return deposit if deposit.errors.any?

    transaction do
      deposit.save!
      confirm(check_credit: false) if quote?
      track_event "deposit_taken", amount: amount_cents, tender: tender
    end
    deposit
  rescue ActiveRecord::RecordInvalid
    deposits.reset
    deposit
  end

  # The order is locked first, so two refunds (or a refund and the deposit paying at the till) can't
  # both spend the same deposit.
  def refund_deposit(amount_cents:, tender:, reference: nil, shift: nil)
    deposit = nil
    transaction do
      lock!
      deposit = deposits.build(account: account, amount_cents: -amount_cents.to_i, tender: tender, reference: reference.presence, shift: shift)
      if amount_cents.to_i > deposit_balance_cents
        deposit.errors.add :amount, "is more than the #{Money.format(deposit_balance_cents)} deposit held"
      end
      next deposit if deposit.errors.any?

      deposit.save!
      track_event "deposit_refunded", amount: amount_cents, tender: tender
      deposit
    end
  rescue ActiveRecord::RecordInvalid
    deposits.reset
    deposit
  end

  def collectable?
    ((quote? && !expired?) || ordered? || ready?) && lines.any? { _1.remaining_quantity.positive? }
  end

  # Puts the order into an empty cart at the prices agreed. Anything else the customer picks
  # up can be scanned in on top as usual.
  # The order is locked, so two tills can't both load it and sell it twice.
  def load_into(sale)
    errors.clear
    sale.transaction do
      lock!
      if !collectable?
        errors.add :base, "This #{kind.downcase} can't be collected"
      elsif sale.lines.any?
        errors.add :base, "Finish or park the sale on the till first"
      elsif (elsewhere = Sale.where(customer_order_id: id, status: %w[ open parked ]).where.not(id: sale.id).first)
        errors.add :base, "This #{kind.downcase} is already on #{elsewhere.register.name}'s till"
      end
      next if errors.any?

      sale.update!(customer_order: self, customer: customer, job: job&.open? ? job : nil)
      lines.reject(&:collected?).each do |line|
        sale.lines.create!(account: account, product: line.product, product_unit: line.product_unit, quantity: line.remaining_quantity,
          unit_price_cents: line.unit_price_cents, detail: line.detail, customer_order_line_id: line.id)
      end
      sale.recalculate
    end
    errors.none?
  end

  # The sale that collected (some of) the order has completed. Each order line notes how much of it went; the
  # order is collected once nothing is left, otherwise it stays ready with the rest still waiting, so a contractor
  # taking 40 of 100 bags today isn't marked as having had them all.
  def mark_collected(sale)
    taken = sale.lines.select(&:customer_order_line_id).group_by(&:customer_order_line_id)
    return if taken.empty?

    lines.each do |line|
      next unless (sold = taken[line.id])
      line.update_columns collected_quantity: [ line.collected_quantity + sold.sum(&:quantity), line.quantity ].min, updated_at: Time.current
    end

    if lines.reload.all?(&:collected?)
      update!(status: :collected, collected_at: sale.completed_at || Time.current)
      track_event "collected", receipt_number: sale.receipt_number
    else
      update!(status: :ready) unless ready?
      track_event "part_collected", receipt_number: sale.receipt_number,
        remaining: lines.reject(&:collected?).map { "#{_1.remaining_quantity.to_s("F").delete_suffix(".0")} × #{_1.description}" }
    end
  end

  # A voided collection puts the goods back on the shelf, so what it took is waiting again.
  def reopen(sale = nil)
    return false unless collected? || ready?

    if sale
      sale.lines.select(&:customer_order_line_id).group_by(&:customer_order_line_id).each do |line_id, sold|
        line = lines.find { _1.id == line_id } or next
        line.update_columns collected_quantity: [ line.collected_quantity - sold.sum(&:quantity), 0 ].max, updated_at: Time.current
      end
    elsif collected?
      lines.update_all(collected_quantity: 0)
    end
    update!(status: :ready, collected_at: nil)
  end
end
