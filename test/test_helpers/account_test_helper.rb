module AccountTestHelper
  # Fixture accessors run outside any account, so look records up with isolation bypassed.
  def branches(*) = Account.without_isolation { super }
  def memberships(*) = Account.without_isolation { super }
end

module AccountIntegrationTestHelper
  # Points requests at a shop's subdomain, e.g. acme.localhost.
  def use_account(account)
    host! "#{account.subdomain}.localhost"
  end

  def use_apex_domain
    host! "localhost"
  end
end

ActiveSupport.on_load(:active_support_test_case) do
  include AccountTestHelper
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include AccountIntegrationTestHelper
end
