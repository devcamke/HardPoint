class CreateProductImports < ActiveRecord::Migration[8.1]
  def change
    # The uploaded CSV is kept in the row itself, so it's protected by row-level security like everything else.
    create_table :product_imports do |t|
      t.references :account, null: false, index: false
      t.references :creator
      t.references :branch
      t.string :status, null: false, default: "checking"
      t.string :filename
      t.text :csv, null: false
      t.integer :rows_count, null: false, default: 0
      t.integer :created_count, null: false, default: 0
      t.integer :updated_count, null: false, default: 0
      t.jsonb :problems, null: false, default: []
      t.jsonb :preview, null: false, default: []
      t.timestamps
    end
    add_index :product_imports, %i[ account_id created_at ]

    add_foreign_key :product_imports, :accounts, deferrable: :immediate
    add_foreign_key :product_imports, :users, column: :creator_id, deferrable: :immediate
    add_foreign_key :product_imports, :branches, deferrable: :immediate

    enable_row_level_security :product_imports
  end
end
