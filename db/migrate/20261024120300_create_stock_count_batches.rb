class CreateStockCountBatches < ActiveRecord::Migration[8.1]
  def change
    # Batch-tracked products are counted batch by batch: one row per batch in stock when the count
    # started, one for stock not in a batch (number nil), and any batches found on the shelf.
    create_table :stock_count_batches do |t|
      t.references :account, null: false, index: false
      t.references :stock_count_line, null: false, index: false
      t.references :stock_batch
      t.string :number
      t.date :expires_on
      t.decimal :expected_quantity, precision: 14, scale: 3, null: false, default: 0
      t.decimal :counted_quantity, precision: 14, scale: 3
      t.timestamps
    end
    add_index :stock_count_batches, %i[ stock_count_line_id number ], unique: true, nulls_not_distinct: true
    add_index :stock_count_batches, :account_id

    add_foreign_key :stock_count_batches, :accounts, deferrable: :immediate
    add_foreign_key :stock_count_batches, :stock_count_lines, deferrable: :immediate
    add_foreign_key :stock_count_batches, :stock_batches, deferrable: :immediate
    enable_row_level_security :stock_count_batches
  end
end
