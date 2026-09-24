# The X report (while the shift is open) and Z report (once it's closed).
class ShiftReport
  attr_reader :shift

  def initialize(shift)
    @shift = shift
  end

  def completed_sales
    shift.sales.completed
  end

  def sales_count
    completed_sales.count
  end

  def voided_count
    shift.sales.voided.count
  end

  def gross_cents
    completed_sales.sum(:subtotal_cents)
  end

  def discount_cents
    completed_sales.sum(:discount_cents) + SaleLine.where(sale: completed_sales).sum(:discount_cents)
  end

  def net_cents
    completed_sales.sum(:total_cents)
  end

  def tax_cents
    completed_sales.sum(:tax_cents)
  end

  def takings_by_tender
    Payment.where(sale: completed_sales).group(:tender).sum(:amount_cents)
  end

  def refunds_by_method
    shift.sale_returns.group(:refund_method).sum(:total_cents)
  end

  def deposits_by_tender
    shift.deposits.group(:tender).sum(:amount_cents)
  end

  def account_payments_by_method
    shift.customer_payments.group(:payment_method).sum(:amount_cents)
  end

  def returns_count
    shift.sale_returns.count
  end

  def cash_movements
    shift.cash_movements.order(:created_at)
  end

  def expected_cash_cents
    shift.closed? ? shift.expected_cash_cents : shift.expected_cash_cents_now
  end
end
