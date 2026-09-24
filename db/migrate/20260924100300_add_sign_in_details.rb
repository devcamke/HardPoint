class AddSignInDetails < ActiveRecord::Migration[8.1]
  def change
    change_table :sessions do |t|
      t.string :sign_in_method, null: false, default: "password"
      t.references :impersonator, index: false
      t.datetime :expires_at
    end
    add_foreign_key :sessions, :users, column: :impersonator_id, deferrable: :immediate

    change_table :memberships do |t|
      t.string :pin_digest
      t.integer :failed_pin_attempts, null: false, default: 0
    end
  end
end
