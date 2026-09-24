class CreateAdminSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :admin, :boolean, null: false, default: false

    # Platform administrators sign in separately, on admin.<domain>. These sessions belong to no shop.
    create_table :admin_sessions do |t|
      t.references :user, null: false
      t.string :ip_address
      t.string :user_agent

      t.timestamps
    end
    add_foreign_key :admin_sessions, :users, deferrable: :immediate
  end
end
