class AddSupplierPaymentToCashMovements < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # A payout from the till that paid a supplier's bill, and the payment to the supplier it was
    # recorded as, so the profit and loss doesn't count it as an expense on top of the goods.
    add_column :cash_movements, :supplier_payment_id, :bigint
    add_index :cash_movements, :supplier_payment_id, algorithm: :concurrently
    add_foreign_key :cash_movements, :supplier_payments, deferrable: :immediate, validate: false
  end
end
