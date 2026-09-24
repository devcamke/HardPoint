class CreateMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :memberships do |t|
      t.references :account, null: false
      t.references :user, null: false
      t.string :role, null: false, default: "cashier"

      t.timestamps
    end
    add_foreign_key :memberships, :accounts, deferrable: :immediate
    add_foreign_key :memberships, :users, deferrable: :immediate
    add_index :memberships, %i[ account_id user_id ], unique: true

    enable_row_level_security :memberships
  end
end
