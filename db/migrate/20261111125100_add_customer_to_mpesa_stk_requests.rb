class AddCustomerToMpesaStkRequests < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # A prompt sent from the customer portal pays the customer's account, not a sale at a till: it names the
    # customer (and the link it came from) instead of a sale, and the payment on account it became.
    change_column_null :mpesa_stk_requests, :sale_id, true
    add_column :mpesa_stk_requests, :customer_id, :bigint
    add_column :mpesa_stk_requests, :customer_payment_id, :bigint
    add_column :mpesa_stk_requests, :portal_link_id, :bigint
    add_index :mpesa_stk_requests, :customer_id, algorithm: :concurrently
    add_index :mpesa_stk_requests, :customer_payment_id, algorithm: :concurrently
    add_index :mpesa_stk_requests, :portal_link_id, algorithm: :concurrently
    add_foreign_key :mpesa_stk_requests, :customers, deferrable: :immediate, validate: false
    add_foreign_key :mpesa_stk_requests, :customer_payments, deferrable: :immediate, validate: false
    add_foreign_key :mpesa_stk_requests, :portal_links, deferrable: :immediate, validate: false
    add_check_constraint :mpesa_stk_requests, "sale_id IS NOT NULL OR customer_id IS NOT NULL", name: "mpesa_stk_requests_pay_something", validate: false
  end
end
