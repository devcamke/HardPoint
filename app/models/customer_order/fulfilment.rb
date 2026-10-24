module CustomerOrder::Fulfilment
  extend ActiveSupport::Concern

  def confirm
    return false unless quote?

    if expired?
      errors.add :base, "This quote expired on #{valid_until.to_fs(:long)}. Change its date to confirm it at the same prices"
      return false
    end

    update(status: :ordered, ordered_at: Time.current).tap { |confirmed| track_event "confirmed", total: total_cents if confirmed }
  end

  def mark_ready
    ordered? && !tools_out? && update(status: :ready).tap { |ready| track_event "ready" if ready }
  end

  # A deposit still held has to be refunded (or kept, by recording that) before cancelling.
  def cancel(reason: nil)
    return false unless quote? || ordered? || ready?

    if deposit_balance_cents.positive?
      errors.add :base, "Refund the #{Money.format(deposit_balance_cents)} deposit first"
      return false
    end

    update(status: :cancelled).tap { |cancelled| track_event "cancelled", reason: reason if cancelled }
  end

  def takes_deposits?
    quote? || ordered? || ready?
  end

  # Deposits paid, less refunds, less what's been used towards the sale that collected the order.
  def deposit_balance_cents
    deposits.sum(:amount_cents) - Payment.deposit.joins(:sale).where(sales: { customer_order_id: id, status: "completed" }).sum(:amount_cents)
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
      confirm if quote?
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
    ((quote? && !expired?) || ordered? || ready?) && !tools_out?
  end

  # A hire order is settled once its tools are back.
  def tools_out?
    source == "hire" && hire_agreement&.out?
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
      lines.each do |line|
        sale.lines.create!(account: account, product: line.product, product_unit: line.product_unit, quantity: line.quantity,
          unit_price_cents: line.unit_price_cents, detail: line.detail, customer_order_line_id: line.id)
      end
      sale.recalculate
    end
    errors.none?
  end

  def mark_collected(sale)
    update!(status: :collected, collected_at: sale.completed_at || Time.current)
    track_event "collected", receipt_number: sale.receipt_number
  end

  # A voided collection puts the goods back on the shelf, so the order is waiting again.
  def reopen
    collected? && update!(status: :ready, collected_at: nil)
  end
end
