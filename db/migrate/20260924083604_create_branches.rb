class CreateBranches < ActiveRecord::Migration[8.1]
  def change
    create_table :branches do |t|
      t.references :account, null: false
      t.string :name, null: false
      t.string :address
      t.string :phone

      t.timestamps
    end
    add_foreign_key :branches, :accounts, deferrable: :immediate
    add_index :branches, %i[ account_id name ], unique: true

    enable_row_level_security :branches
  end
end
