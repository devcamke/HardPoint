class CreateUsageCounts < ActiveRecord::Migration[8.1]
  def change
    # How often each shop uses the shortcuts from docs/SIMPLIFY.md, one row per shop, shortcut and day.
    # Counts only: no user, no search text, nothing a shop would mind us seeing.
    create_table :usage_counts do |t|
      t.references :account, null: false, index: false
      t.string :name, null: false
      t.date :on, null: false
      t.integer :count, null: false, default: 0
      t.timestamps
    end
    add_index :usage_counts, %i[ account_id name on ], unique: true
    add_index :usage_counts, %i[ on name ]

    add_foreign_key :usage_counts, :accounts, deferrable: :immediate
    enable_row_level_security :usage_counts
  end
end
