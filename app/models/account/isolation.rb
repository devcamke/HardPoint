# Keeps Postgres' row-level security settings in step with the current account.
# See config/initializers/row_level_security.rb for the policies themselves.
module Account::Isolation
  extend ActiveSupport::Concern

  class_methods do
    # Called from Current.account= — every tenant query after this only sees this account's rows.
    def isolate_to(account)
      set_row_level_security "app.current_account_id", account&.id.to_s
    end

    # Only for work that legitimately spans accounts: fixtures, seeds, data migrations,
    # platform administration, and a user's own cross-account records (e.g. their sessions).
    def without_isolation
      previous = set_row_level_security("app.bypass_rls", "on")
      yield
    ensure
      set_row_level_security "app.bypass_rls", previous.presence || "off"
    end

    # Runs the block against the read replica, for reads that can be a few seconds behind (reports,
    # exports). The replica's connection has its own settings, so the current account (or bypass)
    # is set on it on the way in and cleared on the way out. Nothing in the block can write.
    def reading
      return yield if ApplicationRecord.connected_to?(role: :reading)

      account_id, bypass = lease_connection.uncached do
        lease_connection.select_rows("SELECT current_setting('app.current_account_id', true), current_setting('app.bypass_rls', true)").first
      end

      ApplicationRecord.connected_to(role: :reading) do
        set_row_level_security "app.current_account_id", account_id.to_s
        set_row_level_security "app.bypass_rls", bypass.presence || "off"
        yield
      ensure
        clear_row_level_security(lease_connection) unless shared_with_writer?
      end
    end

    # Clears the settings if this thread holds a connection, without checking one out.
    def release_isolation
      [ connection_handler.retrieve_connection_pool(connection_specification_name, role: :writing),
        connection_handler.retrieve_connection_pool(connection_specification_name, role: :reading) ].compact.uniq.each do |pool|
        pool.active_connection&.execute "SELECT set_config('app.current_account_id', '', false)"
      end
    end

    private
      def clear_row_level_security(connection)
        connection.execute "SELECT set_config('app.current_account_id', '', false), set_config('app.bypass_rls', 'off', false)"
      end

      # In tests the replica's pool is the writer's (see ActiveRecord::TestFixtures), so its
      # settings belong to the surrounding code and are left as they were.
      def shared_with_writer?
        connection_handler.retrieve_connection_pool(connection_specification_name, role: :reading) ==
          connection_handler.retrieve_connection_pool(connection_specification_name, role: :writing)
      end

      # Uses execute rather than select_value: the query cache must neither skip these
      # statements nor keep serving results cached under the previous setting.
      def set_row_level_security(name, value)
        connection = lease_connection
        previous = connection.uncached { connection.select_value("SELECT current_setting(#{connection.quote(name)}, true)") }
        connection.execute "SELECT set_config(#{connection.quote(name)}, #{connection.quote(value)}, false)"
        previous
      end
  end
end
