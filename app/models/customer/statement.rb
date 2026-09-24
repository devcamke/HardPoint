# A customer's statement for a period: the balance brought forward, each account sale, return
# credited and payment in the period with a running balance, and the ageing at the end.
class Customer::Statement
  Entry = Data.define(:date, :description, :reference, :charge_cents, :credit_cents, :balance_cents)

  attr_reader :customer, :from, :to

  def initialize(customer, from:, to:)
    @customer = customer
    @from = from.to_date
    @to = [ to.to_date, from.to_date ].max
  end

  def opening_balance_cents
    transactions.select { _1[:date] < from }.sum { _1[:charge] - _1[:credit] }
  end

  def entries
    balance = opening_balance_cents
    transactions.select { _1[:date].between?(from, to) }.map do |transaction|
      balance += transaction[:charge] - transaction[:credit]
      Entry.new(transaction[:date], transaction[:description], transaction[:reference], transaction[:charge], transaction[:credit], balance)
    end
  end

  def closing_balance_cents
    entries.last&.balance_cents || opening_balance_cents
  end

  def ageing
    customer.ageing(as_of: to)
  end

  def filename
    "#{customer.name.parameterize}-statement-#{to.strftime("%Y-%m-%d")}.pdf"
  end

  private
    def transactions
      @transactions ||= (sales + returns + payments).select { _1[:date] <= to }.sort_by { [ _1[:date], _1[:order] ] }
    end

    def sales
      customer.account_sales.map do |sale, amount|
        { date: local_date(sale.completed_at), order: 0, description: "Sale", reference: sale.receipt_number, charge: amount, credit: 0 }
      end
    end

    def returns
      customer.account_returns.includes(:branch).map do |sale_return|
        { date: local_date(sale_return.created_at), order: 1, description: "Return credited", reference: sale_return.return_number, charge: 0, credit: sale_return.total_cents }
      end
    end

    def payments
      customer.customer_payments.map do |payment|
        { date: payment.paid_on, order: 2, description: "Payment, #{payment.payment_method.humanize.downcase}", reference: payment.reference.to_s, charge: 0, credit: payment.amount_cents }
      end
    end

    def local_date(time)
      time.in_time_zone(customer.account.time_zone).to_date
    end
end
