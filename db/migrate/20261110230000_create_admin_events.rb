class CreateAdminEvents < ActiveRecord::Migration[8.1]
  def change
    # The platform's own audit trail: what HardPoint staff did in the admin area (signing in, making support
    # sign-in links). Platform-wide, so no account_id and no row-level security; the shop concerned, if any, is
    # kept as target_account_id without a foreign key, so the row outlives a deleted shop.
    create_table :admin_events do |t|
      t.references :user, null: false, foreign_key: { deferrable: :immediate }
      t.string :action, null: false
      t.bigint :target_account_id
      t.jsonb :particulars, null: false, default: {}
      t.string :ip_address
      # A support sign-in link's id, and when it was followed: each link works once.
      t.string :token_id
      t.datetime :token_used_at
      t.datetime :created_at, null: false
    end
    add_index :admin_events, :created_at
    add_index :admin_events, :token_id, unique: true
  end
end
