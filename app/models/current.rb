class Current < ActiveSupport::CurrentAttributes
  attribute :account, :session, :user
  attribute :administrator # platform staff, in the admin area
  attribute :api_key       # the key a public API request came with
  delegate :membership, to: :session, allow_nil: true

  resets { Account.release_isolation }

  def account=(account)
    super
    Account.isolate_to(account)
  end

  def session=(session)
    super
    self.user = session&.user
  end
end
