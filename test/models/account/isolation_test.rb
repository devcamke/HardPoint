require "test_helper"

# Row-level security is the database's guarantee that one shop can never read or write another
# shop's rows, even if application code forgets to scope a query through Current.account.
class Account::IsolationTest < ActiveSupport::TestCase
  test "the app's database role is subject to row-level security" do
    role = ActiveRecord::Base.connection.select_one(
      "SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user")

    assert_not role["rolsuper"], "Superusers bypass row-level security; connect as a regular role"
    assert_not role["rolbypassrls"], "BYPASSRLS roles skip row-level security"
  end

  test "every table with an account_id enforces row-level security" do
    unprotected = ActiveRecord::Base.connection.select_values(<<~SQL)
      SELECT c.relname
      FROM information_schema.columns col
      JOIN pg_class c ON c.relname = col.table_name
      JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = col.table_schema
      WHERE col.column_name = 'account_id' AND col.table_schema = 'public'
        AND NOT (c.relrowsecurity AND c.relforcerowsecurity)
    SQL

    assert_empty unprotected, "Add enable_row_level_security to the migration for: #{unprotected.join(", ")}"
  end

  test "foreign keys are deferrable so fixtures load without a superuser" do
    immediate_only = ActiveRecord::Base.connection.select_values(<<~SQL)
      SELECT conrelid::regclass || '.' || conname FROM pg_constraint
      WHERE contype = 'f' AND connamespace = 'public'::regnamespace AND NOT condeferrable
    SQL

    assert_empty immediate_only, "Use foreign_key: { deferrable: :immediate } for: #{immediate_only.join(", ")}"
  end

  test "unscoped queries only see the current account's rows" do
    Current.account = accounts(:acme)

    assert_equal branches(:acme_main, :acme_yard).sort, Branch.all.sort
    assert_raises(ActiveRecord::RecordNotFound) { Branch.find(branches(:bolt_main).id) }
    assert_equal 2, ActiveRecord::Base.connection.select_value("SELECT count(*) FROM branches")
  end

  test "no rows are visible without a current account" do
    assert_equal 0, Branch.count
    assert_equal 0, Membership.count
    assert_equal 0, Session.count
  end

  test "rows can't be written into another account" do
    Current.account = accounts(:acme)

    assert_raises(ActiveRecord::StatementInvalid, match: /row-level security/) do
      Branch.transaction(requires_new: true) { Branch.create!(account: accounts(:bolt), name: "Sneaky") }
    end

    assert_equal 0, Branch.where(id: branches(:bolt_main).id).update_all(name: "Hijacked")
    assert_equal 0, Branch.where(id: branches(:bolt_main).id).delete_all
  end

  test "rows can't be moved into another account" do
    Current.account = accounts(:acme)

    assert_raises(ActiveRecord::StatementInvalid, match: /row-level security/) do
      Branch.transaction(requires_new: true) { branches(:acme_yard).update!(account_id: accounts(:bolt).id) }
    end
  end

  test "switching accounts switches the visible rows" do
    Current.account = accounts(:acme)
    assert_equal 2, Branch.count

    Current.account = accounts(:bolt)
    assert_equal [ branches(:bolt_main) ], Branch.all.to_a
  end

  test "resetting Current clears the account" do
    Current.account = accounts(:acme)
    Current.reset

    assert_equal 0, Branch.count
  end

  test "without_isolation sees every account and restores isolation afterwards" do
    Current.account = accounts(:acme)

    assert_equal 3, Account.without_isolation { Branch.count }
    assert_equal 2, Branch.count
  end
end
