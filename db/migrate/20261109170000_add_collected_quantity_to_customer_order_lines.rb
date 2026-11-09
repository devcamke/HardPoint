class AddCollectedQuantityToCustomerOrderLines < ActiveRecord::Migration[8.1]
  def change
    # How much of each order line has been collected so far, so an order collected in parts keeps the rest waiting
    # rather than being marked collected whole.
    add_column :customer_order_lines, :collected_quantity, :decimal, precision: 14, scale: 3, default: 0, null: false
    up_only do
      # Orders already collected were collected whole. Row-level security applies to the migration's role too.
      safety_assured do
        transaction do
          execute <<~SQL
            SET LOCAL app.bypass_rls = 'on';
            UPDATE customer_order_lines SET collected_quantity = quantity
             WHERE customer_order_id IN (SELECT id FROM customer_orders WHERE status = 'collected')
          SQL
        end
      end
    end
  end
end
