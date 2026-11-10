class CreateCustomerPaymentAllocations < ActiveRecord::Migration[8.1]
  def change
    # Which sales a payment (or write-off) was put against, when it was put against particular ones rather than
    # the oldest first. The balance is still worked out from the whole ledger; allocations only decide which
    # invoices count as settled.
    create_table :customer_payment_allocations do |t|
      t.references :account, null: false
      t.references :customer_payment, null: false
      t.references :sale, null: false
      t.bigint :amount_cents, null: false
      t.timestamps
    end
    # The table is empty, so validating the keys locks nothing worth waiting for.
    safety_assured do
      add_foreign_key :customer_payment_allocations, :accounts, deferrable: :immediate
      add_foreign_key :customer_payment_allocations, :customer_payments, deferrable: :immediate
      add_foreign_key :customer_payment_allocations, :sales, deferrable: :immediate
    end
    enable_row_level_security :customer_payment_allocations
  end
end
