class CreateStockBatches < ActiveRecord::Migration[8.1]
  def change
    # Products that go off or get recalled (paint, adhesives, sealants, chemicals, fertiliser) can
    # be tracked by the manufacturer's batch, with its expiry date.
    add_column :products, :tracks_batches, :boolean, null: false, default: false

    # One batch of a product at a branch, and how much of it is there. The branch's stock level
    # is the sum of its batches plus anything not in a batch (stock from before batches were tracked,
    # or counted in without one).
    create_table :stock_batches do |t|
      t.references :account, null: false
      t.references :branch, null: false, index: false
      t.references :product, null: false
      t.string :number, null: false
      t.date :expires_on
      t.decimal :quantity, precision: 14, scale: 3, null: false, default: 0
      t.timestamps
    end
    add_index :stock_batches, %i[ branch_id product_id number ], unique: true
    add_index :stock_batches, %i[ account_id expires_on ], where: "quantity > 0", name: "index_stock_batches_in_stock_by_expiry"

    add_reference :stock_movements, :stock_batch, index: true
    add_column :goods_receipt_lines, :batch_number, :string
    add_column :goods_receipt_lines, :expires_on, :date

    add_foreign_key :stock_batches, :accounts, deferrable: :immediate
    add_foreign_key :stock_batches, :branches, deferrable: :immediate
    add_foreign_key :stock_batches, :products, deferrable: :immediate
    add_foreign_key :stock_movements, :stock_batches, deferrable: :immediate
    enable_row_level_security :stock_batches
  end
end
