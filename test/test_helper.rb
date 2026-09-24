ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/account_test_helper"

# Fixtures hold rows for several accounts, so they're inserted with row-level security bypassed.
module FixturesAcrossAccounts
  def create_fixtures(...)
    Account.without_isolation { super }
  end
end
ActiveRecord::FixtureSet.singleton_class.prepend FixturesAcrossAccounts

# Rails disables foreign keys while loading fixtures by disabling triggers, which needs a superuser —
# and superusers skip row-level security. Our foreign keys are deferrable instead, so defer them.
module DeferredFixtureForeignKeys
  def disable_referential_integrity
    set_constraints :deferred
    yield
  end
end
ActiveSupport.on_load(:active_record_postgresqladapter) { prepend DeferredFixtureForeignKeys }

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
