# Shared by the screens that put an entry on a customer's account (payments, refunds, write-offs): building
# the entry from the form, including which unpaid sales it's put against.
module CustomerPaymentEntries
  extend ActiveSupport::Concern

  private
    def set_customer
      @customer = Current.account.customers.find(params[:customer_id])
    end

    # The form lists each unpaid sale with an amount box; blank or 0 leaves that sale to the oldest-first settling.
    def build_entry(kind:, permitted:)
      attributes = params.expect(customer_payment: [ *permitted, allocations: {} ])
      allocations = attributes.delete(:allocations).to_h.filter_map do |sale_id, amount|
        cents = Monetary.to_cents(amount).to_i
        { account: Current.account, sale: @customer.sales.find(sale_id), amount_cents: cents } if cents.positive?
      end
      @customer.customer_payments.new(attributes.merge(kind: kind, account: Current.account, allocations_attributes: allocations))
    end

    def owed_now
      balance = @customer.reload.balance_cents
      if balance.positive? then "#{@customer.name} now owes #{Money.format(balance)}."
      elsif balance.negative? then "#{@customer.name} now has #{Money.format(-balance)} of credit."
      else "#{@customer.name} now owes nothing."
      end
    end
end
