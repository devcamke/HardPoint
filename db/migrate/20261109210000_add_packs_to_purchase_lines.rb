class AddPacksToPurchaseLines < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # Goods bought by the pack ("3 boxes of 100 screws"): which of the product's pack sizes the line was
    # entered in, and how many of it. Quantity and unit cost stay in the product's own unit, as stock
    # and costing need them; the pack is for the order, the receipt and the supplier's paperwork.
    add_column :purchase_order_lines, :product_unit_id, :bigint
    add_column :purchase_order_lines, :pack_quantity, :decimal, precision: 14, scale: 3
    add_column :goods_receipt_lines, :product_unit_id, :bigint
    add_column :goods_receipt_lines, :pack_quantity, :decimal, precision: 14, scale: 3
    add_index :purchase_order_lines, :product_unit_id, algorithm: :concurrently
    add_index :goods_receipt_lines, :product_unit_id, algorithm: :concurrently
    add_foreign_key :purchase_order_lines, :product_units, deferrable: :immediate, validate: false
    add_foreign_key :goods_receipt_lines, :product_units, deferrable: :immediate, validate: false
  end
end
