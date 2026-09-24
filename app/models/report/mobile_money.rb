# M-Pesa reconciliation: what Safaricom says arrived against what the shop recorded. Money that
# arrived but was never used on a sale, order or account needs chasing; codes typed at a till
# that Safaricom never confirmed may be mistakes or fakes.
class Report::MobileMoney < Report
  self.title = "M-Pesa reconciliation"
  self.description = "Money received on your Paybill or Till against M-Pesa payments recorded at the tills"
  self.group = "Sales and money"

  def sections
    [ Section.new(title: "Summary", columns: [ Column.new("", :text), Column.new("Payments", :count), Column.new("Amount", :money) ], rows: summary_rows,
        note: ("Your Paybill or Till isn't connected yet (Settings › M-Pesa), so there's nothing from Safaricom to check against." if account.mpesa_shortcodes.none?)),
      Section.new(title: "Received but not used", columns: received_columns, rows: unmatched_rows,
        note: "Use these at the till, or check with the customer. Payments to the Paybill with an order number or a customer's phone as the account are matched automatically."),
      Section.new(title: "Recorded at the till but not confirmed by Safaricom", columns: unconfirmed_columns, rows: unconfirmed_rows,
        note: ("Only payments since your first Paybill or Till was connected are checked." if account.mpesa_shortcodes.any?)) ]
  end

  private
    def transactions
      account.mpesa_transactions.where(transacted_at: period.range)
    end

    def summary_rows
      matched = transactions.where.not(matched_id: nil).group(:matched_type).pluck(:matched_type, Arel.sql("COUNT(*)"), Arel.sql("SUM(amount_cents)")).to_h { [ _1, [ _2, _3.to_i ] ] }
      unmatched = transactions.unmatched.pluck(Arel.sql("COUNT(*)"), Arel.sql("COALESCE(SUM(amount_cents), 0)")).first
      [ [ "Received from Safaricom", transactions.count, transactions.sum(:amount_cents) ],
        [ "Used on sales", *matched.fetch("Payment", [ 0, 0 ]) ],
        [ "Deposits on orders", *matched.fetch("Deposit", [ 0, 0 ]) ],
        [ "Payments on account", *matched.fetch("CustomerPayment", [ 0, 0 ]) ],
        [ "Received but not used", unmatched.first, unmatched.last.to_i ],
        [ "Recorded at a till, not confirmed", unconfirmed_payments.count, unconfirmed_payments.sum(:amount_cents) ] ]
    end

    def received_columns
      [ Column.new("When", :text), Column.new("M-Pesa code", :text), Column.new("From", :text), Column.new("Account entered", :text), Column.new("Amount", :money) ]
    end

    def unmatched_rows
      transactions.unmatched.order(:transacted_at).map do |transaction|
        [ I18n.l(transaction.transacted_at, format: :short), transaction.trans_id, transaction.payer, transaction.bill_reference, transaction.amount_cents ]
      end
    end

    def unconfirmed_columns
      [ Column.new("Receipt", :link), Column.new("When", :text), Column.new("Cashier", :text), Column.new("Code typed", :text), Column.new("Amount", :money) ]
    end

    # M-Pesa payments on sales with no matching Safaricom record, once there's a connected
    # shortcode to have received them.
    def unconfirmed_payments
      connected_since = account.mpesa_shortcodes.minimum(:created_at) or return Payment.none
      Payment.mobile_money.where(sale_id: completed_sales.where(completed_at: connected_since..).select(:id))
        .where.not(id: account.mpesa_transactions.where(matched_type: "Payment").select(:matched_id))
    end

    def unconfirmed_rows
      unconfirmed_payments.includes(sale: [ :branch, :cashier ]).order(:created_at).map do |payment|
        [ Link.new(payment.sale.receipt_number, payment.sale), I18n.l(payment.sale.completed_at, format: :short), payment.sale.cashier.name,
          payment.reference, payment.amount_cents ]
      end
    end
end
