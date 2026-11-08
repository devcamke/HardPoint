class AddLastSeenAtToSessions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # When the session last made a request (to the hour), for the idle limit and the signed-in devices list.
    add_column :sessions, :last_seen_at, :datetime
    up_only do
      # Existing sessions count as last seen when they were last updated. Row-level security applies to the
      # migration's role too, so the backfill bypasses it for this one statement. The table holds a few rows per
      # shop, so one statement is fine.
      safety_assured do
        transaction { execute "SET LOCAL app.bypass_rls = 'on'; UPDATE sessions SET last_seen_at = updated_at WHERE last_seen_at IS NULL" }
      end
    end
    add_index :sessions, %i[ account_id user_id ], algorithm: :concurrently
  end
end
