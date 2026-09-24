class CreateSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :sessions do |t|
      t.references :account, null: false
      t.references :user, null: false
      t.string :ip_address
      t.string :user_agent

      t.timestamps
    end
    add_foreign_key :sessions, :accounts, deferrable: :immediate
    add_foreign_key :sessions, :users, deferrable: :immediate

    enable_row_level_security :sessions
  end
end
