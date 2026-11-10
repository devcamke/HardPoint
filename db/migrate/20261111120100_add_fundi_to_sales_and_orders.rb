class AddFundiToSalesAndOrders < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Who brought the customer: named at the till, or on a quote or order and carried to its sale. Indexed
  # concurrently so the till keeps selling while the index is built.
  def change
    add_reference :sales, :fundi, index: { algorithm: :concurrently }
    add_reference :customer_orders, :fundi, index: { algorithm: :concurrently }
  end
end
