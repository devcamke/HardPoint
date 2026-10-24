class CreateSupplierReturns < ActiveRecord::Migration[8.1]
  def change
    # Goods sent back to a supplier (damaged, wrong, not ordered), with the debit note that goes with
    # them. Recording one takes the goods out of stock and what they're worth off what's owed to the
    # supplier; the supplier's credit note number is noted when it arrives.
    create_table :supplier_returns do |t|
      t.references :account, null: false, index: false
      t.references :supplier, null: false
      t.references :branch, null: false, index: false
      t.references :goods_receipt
      t.references :creator
      t.integer :number, null: false
      t.string :reason, null: false
      t.string :note
      t.bigint :total_cents, null: false, default: 0
      t.bigint :tax_cents, null: false, default: 0
      t.decimal :exchange_rate, precision: 18, scale: 8
      t.string :credit_note_number
      t.date :credited_on
      t.timestamps
    end
    add_index :supplier_returns, %i[ branch_id number ], unique: true
    add_index :supplier_returns, %i[ account_id created_at ]

    create_table :supplier_return_lines do |t|
      t.references :account, null: false
      t.references :supplier_return, null: false
      t.references :product, null: false
      t.references :stock_batch
      t.decimal :quantity, precision: 14, scale: 3, null: false
      t.bigint :unit_cost_cents, null: false
      t.decimal :tax_rate, precision: 5, scale: 2, null: false, default: 0
      t.bigint :total_cents, null: false, default: 0
      t.bigint :tax_cents, null: false, default: 0
    end

    { supplier_returns: %i[ accounts suppliers branches goods_receipts ], supplier_return_lines: %i[ accounts supplier_returns products stock_batches ] }.each do |table, references|
      references.each { add_foreign_key table, _1, deferrable: :immediate }
      enable_row_level_security table
    end
    add_foreign_key :supplier_returns, :users, column: :creator_id, deferrable: :immediate
  end
end
