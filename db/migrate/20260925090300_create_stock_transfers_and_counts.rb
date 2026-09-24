class CreateStockTransfersAndCounts < ActiveRecord::Migration[8.1]
  def change
    create_table :stock_transfers do |t|
      t.references :account, null: false, index: false
      t.references :from_branch, null: false
      t.references :to_branch, null: false
      t.references :sender
      t.references :receiver
      t.string :status, null: false, default: "in_transit"
      t.string :note
      t.datetime :sent_at
      t.datetime :received_at
      t.timestamps
    end
    add_index :stock_transfers, %i[ account_id created_at ]

    create_table :stock_transfer_lines do |t|
      t.references :account, null: false, index: false
      t.references :stock_transfer, null: false, index: false
      t.references :product, null: false
      t.decimal :quantity, precision: 14, scale: 3, null: false
      t.timestamps
    end
    add_index :stock_transfer_lines, %i[ stock_transfer_id product_id ], unique: true

    create_table :stock_counts do |t|
      t.references :account, null: false, index: false
      t.references :branch, null: false
      t.references :category
      t.references :creator
      t.references :approver
      t.string :status, null: false, default: "counting"
      t.string :note
      t.datetime :submitted_at
      t.datetime :approved_at
      t.timestamps
    end
    add_index :stock_counts, %i[ account_id created_at ]

    create_table :stock_count_lines do |t|
      t.references :account, null: false, index: false
      t.references :stock_count, null: false, index: false
      t.references :product, null: false
      t.decimal :expected_quantity, precision: 14, scale: 3, null: false
      t.decimal :counted_quantity, precision: 14, scale: 3
      t.timestamps
    end
    add_index :stock_count_lines, %i[ stock_count_id product_id ], unique: true

    add_foreign_key :stock_transfers, :accounts, deferrable: :immediate
    add_foreign_key :stock_transfers, :branches, column: :from_branch_id, deferrable: :immediate
    add_foreign_key :stock_transfers, :branches, column: :to_branch_id, deferrable: :immediate
    add_foreign_key :stock_transfers, :users, column: :sender_id, deferrable: :immediate
    add_foreign_key :stock_transfers, :users, column: :receiver_id, deferrable: :immediate
    add_foreign_key :stock_transfer_lines, :accounts, deferrable: :immediate
    add_foreign_key :stock_transfer_lines, :stock_transfers, deferrable: :immediate
    add_foreign_key :stock_transfer_lines, :products, deferrable: :immediate
    add_foreign_key :stock_counts, :accounts, deferrable: :immediate
    add_foreign_key :stock_counts, :branches, deferrable: :immediate
    add_foreign_key :stock_counts, :categories, deferrable: :immediate
    add_foreign_key :stock_counts, :users, column: :creator_id, deferrable: :immediate
    add_foreign_key :stock_counts, :users, column: :approver_id, deferrable: :immediate
    add_foreign_key :stock_count_lines, :accounts, deferrable: :immediate
    add_foreign_key :stock_count_lines, :stock_counts, deferrable: :immediate
    add_foreign_key :stock_count_lines, :products, deferrable: :immediate

    %i[ stock_transfers stock_transfer_lines stock_counts stock_count_lines ].each { |table| enable_row_level_security table }
  end
end
