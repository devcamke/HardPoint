class AddKindToCustomerPayments < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # An entry on a customer's account is money paid in (payment), credit handed back to them (refund) or a debt
    # the shop has given up on (write_off). A write-off isn't money, so it has no payment method; it has the
    # manager who approved it and why instead.
    add_column :customer_payments, :kind, :string, null: false, default: "payment"
    add_column :customer_payments, :reason, :string
    add_column :customer_payments, :approver_id, :bigint
    add_index :customer_payments, :approver_id, algorithm: :concurrently
    add_foreign_key :customer_payments, :users, column: :approver_id, deferrable: :immediate, validate: false
    change_column_null :customer_payments, :payment_method, true
  end
end
