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
  # Putting more on account than the customer's credit allows needs an owner's or manager's
  # approval (credit_approver). Once the total is covered the sale completes.
  def pay(tender:, amount_cents: nil, tendered_cents: nil, reference: nil, credit_approver: nil)
    raise ArgumentError, "This sale can't take payments" unless open?

    lines.reload
    due = balance_due_cents
    # Built outside the association so a refused payment never counts towards what's paid.
    payment = Payment.new(account: account, sale: self, tender: tender, reference: reference.presence)

    if tender.to_s == "cash"
      payment.tendered_cents = tendered_cents || amount_cents || due
      payment.amount_cents = [ payment.tendered_cents.to_i, due ].min
    elsif tender.to_s == "deposit"
      payment.amount_cents = [ amount_cents || due, due, deposit_available_cents ].min
      payment.errors.add :base, "There's no deposit to use on this sale" unless payment.amount_cents.positive?
    else
      payment.amount_cents = amount_cents || due
      payment.errors.add :amount, "is more than the #{Money.format(due)} due" if payment.amount_cents > due
    end

    check_account_credit(payment, credit_approver) if payment.on_account?
    check_ready_to_complete(payment) if payment.amount_cents.to_i >= due
    return payment if payment.errors.any?

    transaction do
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

  def remove_payment(payment)
    raise ArgumentError, "This sale can't be changed" unless open?
    payment.destroy
  end

  def over_credit_limit?(payment)
    customer && payment.amount_cents.to_i > customer.available_credit_cents
  end

  private
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
      track_event "credit_approved", approver: approver.name, customer: customer.name, amount: payment.amount_cents,
        available: customer.available_credit_cents
    end

    def check_ready_to_complete(payment)
      missing_serials = lines.select { |line| line.product.serialized? && line.serial_number.blank? }

      if lines.empty?
        payment.errors.add :base, "Add something to sell first"
      elsif missing_serials.any?
        payment.errors.add :base, "Enter the serial number for #{missing_serials.map { _1.product.name }.to_sentence}"
      end
    end

    # Numbering and stock happen together, so a completed sale always has both.
    def complete
      lock!
      # Whoever takes the final payment served the customer (the till may have switched users).
      self.cashier = Current.user if Current.user
      self.number = DocumentSequence.next_number(branch, "sale")
      lines.each(&:deduct_stock)
      update! status: :completed, completed_at: happened_at || Time.current
      customer_order&.mark_collected(self)
    end
end
