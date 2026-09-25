require "test_helper"

# Reads from the replica use their own connection, which starts with no account set. These tests
# run outside a transaction, so the replica connection is a real second connection that only sees
# committed rows, as in production.
class Account::ReplicaReadingTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup { Current.account = accounts(:acme) }
  teardown { Current.reset }

  def acme_products = Account.without_isolation { Product.where(account: accounts(:acme)).count }
  def replica_setting = ApplicationRecord.connected_to(role: :reading) { ApplicationRecord.lease_connection.select_value("SELECT current_setting('app.current_account_id', true)") }

  test "the replica is a separate connection, and on its own it sees nothing" do
    writer = ApplicationRecord.lease_connection
    assert_not_same writer, ApplicationRecord.connected_to(role: :reading) { ApplicationRecord.lease_connection }
    assert_equal 0, ApplicationRecord.connected_to(role: :reading) { Product.count }, "no account set: fail closed"
  end

  test "Account.reading carries the account to the replica, and clears it afterwards" do
    assert_operator acme_products, :>, 0
    assert_equal acme_products, Account.reading { Product.count }
    assert_equal [ accounts(:acme).id ], Account.reading { Product.distinct.pluck(:account_id) }
    assert_equal "", replica_setting.to_s
  end

  test "bypassing isolation carries across, and the replica can't be written to" do
    all = Account.without_isolation { Product.count }
    assert_equal all, Account.without_isolation { Account.reading { Product.count } }
    assert_raises(ActiveRecord::ReadOnlyError) { Account.reading { Product.first.update!(name: "Changed on a replica") } }
  end

  test "reports read from the replica" do
    report = Report::Sales.new(account: accounts(:acme), period: Report::Period.for_preset("this_month"))
    assert_equal report.sections.map(&:rows), Account.reading { report.class.new(account: accounts(:acme), period: report.period).sections.map(&:rows) }
  end
end
