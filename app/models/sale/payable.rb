module Sale::Payable
  extend ActiveSupport::Concern

  included do
    has_many :payments, -> { order(:id) }, dependent: :destroy
  end

  def paid_cents
    payments.select(&:persisted?).sum(&:amount_cents)
  end

  def balance_due_cents
    total_cents - paid_cents
  end

  def change_cents
    payments.select(&:persisted?).sum(&:change_cents)
  end

  # The deposit on the order being collected that hasn't been used on this sale yet.
  def deposit_available_cents
    return 0 unless customer_order

    customer_order.deposit_balance_cents - payments.select { _1.persisted? && _1.deposit? }.sum(&:amount_cents)
  end

  # Takes a payment. Cash can be more than what's due (the rest is change); other tenders can't.
  # cash_limit_cents caps what cash pays, for an offline sale whose till already gave the change.
  # Putting more on account than the customer's credit allows needs an owner's or manager's
  # approval (credit_approver). Once the total is covered the sale completes.
  #
  # The sale is locked and reloaded first, so two payments arriving at once (a double tap, an M-Pesa
  # callback as the cashier takes a card) are taken one after the other, and the second sees what the
  # first did. Points and account payments also lock the customer, and deposits the order, so two
  # tills can't both spend the same balance.
  def pay(tender:, amount_cents: nil, tendered_cents: nil, reference: nil, credit_approver: nil, currency: nil, foreign_tendered_cents: nil, cash_limit_cents: nil)
    raise ArgumentError, "This sale can't take payments" unless open?

    transaction do
      lock!
      raise ArgumentError, "This sale can't take payments" unless open?

      take_payment(tender:, amount_cents:, tendered_cents:, reference:, credit_approver:, currency:, foreign_tendered_cents:, cash_limit_cents:)
    end
  end

  def take_payment(tender:, amount_cents:, tendered_cents:, reference:, credit_approver:, currency:, foreign_tendered_cents:, cash_limit_cents:)
    reload_lines
    payments.reset
    customer&.lock! if tender.to_s == "on_account"
    customer_order&.lock! if tender.to_s == "deposit"
    due = balance_due_cents
    # Built outside the association so a refused payment never counts towards what's paid.
    payment = Payment.new(account: account, sale: self, tender: tender, reference: reference.presence)

    if tender.to_s == "cash"
      payment.tendered_cents = tendered_cents || amount_cents || due
      payment.amount_cents = [ payment.tendered_cents.to_i, due, cash_limit_cents ].compact.min
    elsif tender.to_s == "points"
      # A till that hasn't reloaded since loyalty points were removed may still offer them.
      payment.errors.add :base, "Loyalty points are no longer taken"
    elsif tender.to_s == "foreign_cash"
      take_foreign_cash(payment, currency, foreign_tendered_cents, due)
    elsif tender.to_s == "deposit"
      payment.amount_cents = [ amount_cents || due, due, deposit_available_cents ].min
      payment.errors.add :base, "There's no deposit to use on this sale" unless payment.amount_cents.positive?
    elsif tender.to_s.in?(%w[ mobile_money airtel_money ]) && tendered_cents.to_i > (amount_cents || due)
      # The phone sent more than was asked: the sale takes what's due and the rest is change, in cash.
      payment.tendered_cents = tendered_cents
      payment.amount_cents = [ amount_cents || due, due ].min
    else
      payment.amount_cents = amount_cents || due
      payment.tendered_cents = payment.amount_cents if tender.to_s.in?(%w[ mobile_money airtel_money ])
      payment.errors.add :amount, "is more than the #{Money.format(due)} due" if payment.amount_cents > due
    end

    check_account_credit(payment, credit_approver) if payment.on_account?
    check_ready_to_complete(payment) if payment.amount_cents.to_i >= due
    return payment if payment.errors.any?

    transaction(requires_new: true) do
      approve_credit(payment, credit_approver) if payment.on_account? && over_credit_limit?(payment)
      payment.save!
      payments.reset
      complete if balance_due_cents <= 0
    end
    payment
  rescue ActiveRecord::RecordInvalid
    payments.reset
    payment
  end
  private :take_payment

  def remove_payment(payment)
    raise ArgumentError, "This sale can't be changed" unless open?
    payment.destroy
  end

  # A sale that comes to nothing (a replacement under warranty discounted to zero, a bundle's free item on its own)
  # has no payment to complete it through, so an owner or manager completes it by hand, and Activity says who. The
  # same checks as a final payment apply: something on the sale, serial numbers, in-date stock, an approved discount.
  def complete_without_payment(approver:)
    raise ArgumentError, "This sale can't be completed" unless open?

    transaction do
      lock!
      raise ArgumentError, "This sale can't be completed" unless open?

      reload_lines
      payments.reset
      errors.clear
      if balance_due_cents.positive?
        errors.add :base, "#{Money.format(balance_due_cents)} is still due on this sale; take a payment instead"
      else
        check_ready_to_complete(self)
      end
      return false if errors.any?

      complete
      track_event "completed_without_payment", approver: approver, total: total_cents
      true
    end
  end

  def over_credit_limit?(payment)
    customer && payment.amount_cents.to_i > customer.available_credit_cents
  end

  private
    # Foreign notes are converted at the shop's rate for that currency, rounded down; the rate is kept.
    def take_foreign_cash(payment, code, foreign_cents, due)
      rate = account.currencies.at_till.find_by(code: code.to_s.upcase)
      if rate.nil?
        payment.errors.add :base, "#{code.presence || "That currency"} isn't taken at the till. Owners and managers add currencies in Settings"
      elsif foreign_cents.to_i <= 0
        payment.errors.add :base, "Enter how much #{rate.code} was handed over"
      else
        payment.assign_attributes(currency: rate.code, exchange_rate: rate.rate, foreign_tendered_cents: foreign_cents,
          tendered_cents: rate.to_base_cents(foreign_cents))
        payment.amount_cents = [ payment.tendered_cents, due ].min
        payment.errors.add :base, "#{Money.format(foreign_cents, currency: rate.code)} is worth less than a cent here" unless payment.amount_cents.positive?
      end
    end

    def check_account_credit(payment, approver)
      if customer.nil?
        payment.errors.add :base, "Choose a customer to put this on account"
      elsif over_credit_limit?(payment) && approver.nil?
        payment.errors.add :base, "#{customer.name} has only #{Money.format(customer.available_credit_cents)} of credit left. " \
          "Going over needs a manager's approval PIN"
      end
    end

    def approve_credit(payment, approver)
      update!(credit_approver: approver)
      track_event "credit_approved", approver: approver, customer: customer.name, amount: payment.amount_cents,
        available: customer.available_credit_cents
    end

    def check_ready_to_complete(payment)
      missing_serials = lines.select { |line| line.product.serialized? && line.serial_number.blank? }
      # Batch-tracked stock is sold in date only; the offline till couldn't have known, so its sales are let through.
      out_of_date = offline_uuid ? [] : lines.select { |line| line.product.tracks_batches? && line.stock_in_date < line.quantity && line.stock_on_hand >= line.quantity }

      if lines.empty?
        payment.errors.add :base, "Add something to sell first"
      elsif missing_serials.any?
        payment.errors.add :base, "Enter the serial number for #{missing_serials.map { _1.product.name }.to_sentence}"
      elsif out_of_date.any?
        line = out_of_date.first
        payment.errors.add :base, "Only #{line.stock_in_date.to_s("F").delete_suffix(".0")} #{line.product.name} here are in date; the rest have expired. " \
          "Write the expired ones off, or sell fewer"
      elsif discount_needs_approval?
        # The till checks this on every change; this catches whatever reached the payment another way.
        payment.errors.add :base, "The discount on this sale is #{highest_discount_percent.round(1).to_s.delete_suffix(".0")}%, " \
          "over the #{account.max_cashier_discount_percent.to_s("F").delete_suffix(".0")}% a cashier can give. It needs a manager's approval PIN"
      end
    end

    # Numbering and stock happen together, so a completed sale always has both.
    def complete
      lock!
      raise ArgumentError, "This sale has already been #{status}" unless open?
      # Whoever takes the final payment served the customer (the till may have switched users).
      self.cashier = Current.user if Current.user
      self.number = DocumentSequence.next_number(branch, "sale")
      lines.each(&:deduct_stock)
      update! status: :completed, completed_at: happened_at || Time.current
      customer_order&.mark_collected(self)
    end
end
