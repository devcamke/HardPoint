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

    # Clears the settings if this thread holds a connection, without checking one out.
    def release_isolation
      if connection = connection_pool.active_connection
        connection.execute "SELECT set_config('app.current_account_id', '', false)"
      end
    end

    private
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
