# An M-Pesa code typed by hand, on a sale's payment, a deposit or a payment on account. A code is money
# once: one already used, or one Safaricom says was for less than is being paid, is refused. A code
# for money that already arrived on the Paybill claims it, so it can't be picked again at a till.
# A code Safaricom hasn't told us about (yet) is taken on trust; on a sale, the M-Pesa report lists it
# as unconfirmed.
module MobileMoneyCode
  extend ActiveSupport::Concern

  included do
    validate :mobile_money_code_is_usable, on: :create, if: :mobile_money_code?
    after_create_commit :claim_mpesa_transaction, if: :mobile_money_code?
  end

  def mobile_money_code
    reference.to_s.strip.upcase.presence
  end

  # Where else a code was used, in words ("on sale MAIN-000042"), or nil.
  def self.used(account, code, except: nil)
    matching = ->(scope) { scope.where("upper(trim(reference)) = ?", code).where.not(id: except&.id) }
    if (payment = matching.(Payment.where(account: account).mobile_money).includes(:sale).first)
      payment.sale.receipt_number ? "on sale #{payment.sale.receipt_number}" : "on another sale"
    elsif (deposit = matching.(account.deposits.where(tender: "mobile_money").where("amount_cents > 0")).includes(:customer_order).first)
      "as a deposit on #{deposit.customer_order.reference}"
    elsif (customer_payment = matching.(account.customer_payments.payments.where(payment_method: "mobile_money")).includes(:customer).first)
      "on #{customer_payment.customer.name}'s account"
    end
  end

  private
    # Each model says when its reference is an M-Pesa code for money coming in, and how much that money must be.
    def mobile_money_code?
      raise NotImplementedError
    end

    def mobile_money_cents
      raise NotImplementedError
    end

    def mobile_money_code_is_usable
      code = mobile_money_code or return

      if (where = MobileMoneyCode.used(account, code, except: self))
        errors.add :base, "M-Pesa code #{code} was already used #{where}"
      elsif (transaction = account.mpesa_transactions.find_by(trans_id: code))
        if transaction.matched && transaction.matched != self
          errors.add :base, "M-Pesa code #{code} was already used"
        elsif transaction.amount_cents < mobile_money_cents.to_i
          errors.add :base, "M-Pesa code #{code} was for #{Money.format(transaction.amount_cents)}, less than the #{Money.format(mobile_money_cents.to_i)} being paid"
        end
      end
    end

    def claim_mpesa_transaction
      account.mpesa_transactions.unmatched.find_by(trans_id: mobile_money_code)&.match(self)
    end
end
