# Postgres row-level security (RLS) is the database-level safety net behind account scoping.
# See docs/PLAN.md §2. Every table with an account_id gets a policy that only exposes rows
# belonging to the account in the `app.current_account_id` setting, which Current.account=
# keeps in sync. With no account set, no rows are visible (fail closed).
module RowLevelSecurity
  module MigrationHelpers
    def enable_row_level_security(table)
      reversible do |direction|
        direction.up do
          execute <<~SQL
            ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY;
            ALTER TABLE #{table} FORCE ROW LEVEL SECURITY;
            CREATE POLICY account_isolation ON #{table}
              USING (#{account_isolation_condition})
              WITH CHECK (#{account_isolation_condition});
          SQL
        end

        direction.down do
          execute <<~SQL
            DROP POLICY IF EXISTS account_isolation ON #{table};
            ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY;
            ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY;
          SQL
        end
      end
    end

    private
      def account_isolation_condition
        "current_setting('app.bypass_rls', true) = 'on' OR " \
          "account_id = NULLIF(current_setting('app.current_account_id', true), '')::bigint"
      end
  end
end

ActiveSupport.on_load(:active_record) do
  ActiveRecord::Migration.include RowLevelSecurity::MigrationHelpers
end

# Never let a pooled connection carry one request's account into the next.
ActiveSupport.on_load(:active_record_postgresqladapter) do
  set_callback :checkout, :after do
    execute "SELECT set_config('app.current_account_id', '', false), set_config('app.bypass_rls', 'off', false)"
  end
end
