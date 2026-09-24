# Every foreign key gets an index led by its column: exports and shop deletion filter by account_id,
# and Postgres checks referencing rows when a parent row is deleted. Built concurrently so a live
# database keeps taking writes.
class IndexForeignKeys < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  ACCOUNT_TABLES = %i[ billing_payments cash_movements customer_order_lines customer_payments deposits document_sequences
    etims_devices etims_item_registrations goods_receipt_lines goods_receipts kit_components mpesa_stk_requests payments
    price_list_items product_units purchase_order_lines sale_lines sale_return_lines stock_adjustments stock_count_lines
    stock_transfer_lines supplier_payments supplier_products ].freeze

  def change
    ACCOUNT_TABLES.each { |table| add_index table, :account_id, algorithm: :concurrently, if_not_exists: true }
    add_index :stock_movements, :branch_id, algorithm: :concurrently, if_not_exists: true
    add_index :sessions, :impersonator_id, algorithm: :concurrently, if_not_exists: true
  end
end
