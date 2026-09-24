class CreateRegisters < ActiveRecord::Migration[8.1]
  def change
    create_table :registers do |t|
      t.references :account, null: false
      t.references :branch, null: false
      t.string :name, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_foreign_key :registers, :accounts, deferrable: :immediate
    add_foreign_key :registers, :branches, deferrable: :immediate
    add_index :registers, %i[ branch_id name ], unique: true

    enable_row_level_security :registers
  end
end
