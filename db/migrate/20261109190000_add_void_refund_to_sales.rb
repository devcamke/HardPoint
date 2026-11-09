class AddVoidRefundToSales < ActiveRecord::Migration[8.1]
  def change
    # How the money went back when a sale was voided (cash from the drawer, an M-Pesa or Airtel Money reversal, a
    # card refund, credit to the customer's account) and the reversal's code. Until now a void only dropped the sale
    # from the takings, taking it that cash had been handed back.
    add_column :sales, :void_refund_method, :string
    add_column :sales, :void_refund_reference, :string
    # An M-Pesa payment reversed after its sale was voided stays matched to that payment, so it isn't offered at the
    # till as money to use, but it's no longer money used on a sale either; reconciliation counts it apart.
    add_column :mpesa_transactions, :refunded_at, :datetime

    up_only do
      # Sales voided before this were taken as refunded the way they were paid, cash first, which is what the drawer
      # maths assumed. Row-level security applies to the migration's role too, so the backfill bypasses it for this
      # one statement.
      safety_assured do
        transaction do
          execute <<~SQL
            SET LOCAL app.bypass_rls = 'on';
            UPDATE sales
               SET void_refund_method = (SELECT CASE WHEN payments.tender = 'foreign_cash' THEN 'cash' ELSE payments.tender END
                                           FROM payments
                                          WHERE payments.sale_id = sales.id AND payments.tender NOT IN ('deposit', 'points')
                                          ORDER BY (payments.tender IN ('cash', 'foreign_cash')) DESC, payments.id LIMIT 1)
             WHERE sales.status = 'voided' AND sales.void_refund_method IS NULL
          SQL
        end
      end
    end
  end
end
