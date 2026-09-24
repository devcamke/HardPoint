class CreateStock < ActiveRecord::Migration[8.1]
  def change
    # Cached balance per product per branch, kept in step with the movement ledger.
    create_table :stock_levels do |t|
      t.references :account, null: false, index: false
      t.references :branch, null: false, index: false
      t.references :product, null: false
      t.decimal :quantity, precision: 14, scale: 3, null: false, default: 0
      t.timestamps
    end
    add_index :stock_levels, %i[ branch_id product_id ], unique: true
    add_index :stock_levels, %i[ account_id product_id ]

    # The append-only ledger: every change to stock, why, and the balance after it.
    create_table :stock_movements do |t|
      t.references :account, null: false, index: false
      t.references :branch, null: false, index: false
      t.references :product, null: false, index: false
      t.references :source, polymorphic: true
      t.references :creator
      t.decimal :quantity, precision: 14, scale: 3, null: false
      t.decimal :balance, precision: 14, scale: 3, null: false
      t.string :reason, null: false
      t.bigint :unit_cost_cents
      t.string :note
      t.datetime :created_at, null: false
    end
    add_index :stock_movements, %i[ product_id branch_id created_at ]
    add_index :stock_movements, %i[ account_id created_at ]

    create_table :stock_adjustments do |t|
      t.references :account, null: false, index: false
      t.references :branch, null: false
      t.references :product, null: false
      t.references :creator
      t.decimal :quantity, precision: 14, scale: 3, null: false
      t.string :reason, null: false
      t.string :note
      t.datetime :created_at, null: false
    end

    add_foreign_key :stock_levels, :accounts, deferrable: :immediate
    add_foreign_key :stock_levels, :branches, deferrable: :immediate
    add_foreign_key :stock_levels, :products, deferrable: :immediate
    add_foreign_key :stock_movements, :accounts, deferrable: :immediate
    add_foreign_key :stock_movements, :branches, deferrable: :immediate
    add_foreign_key :stock_movements, :products, deferrable: :immediate
    add_foreign_key :stock_movements, :users, column: :creator_id, deferrable: :immediate
    add_foreign_key :stock_adjustments, :accounts, deferrable: :immediate
    add_foreign_key :stock_adjustments, :branches, deferrable: :immediate
    add_foreign_key :stock_adjustments, :products, deferrable: :immediate
    add_foreign_key :stock_adjustments, :users, column: :creator_id, deferrable: :immediate

    %i[ stock_levels stock_movements stock_adjustments ].each { |table| enable_row_level_security table }
  end
end
